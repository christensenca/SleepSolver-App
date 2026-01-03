//
//  HealthMetricsManager.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/30/25.
//

import Foundation
import HealthKit
import CoreData

class HealthMetricsManager {
    static let shared = HealthMetricsManager()
    private let healthStore = HKHealthStore()

    // Define all health metric types
    private let wristTemperatureType = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!
    private let typesToRead: Set<HKObjectType> = [
        HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!,
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
        HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!
    ]

    private var anchorKey: String { "healthMetricsAnchor_wristTemperature" }

    private var anchor: HKQueryAnchor? {
        get {
            guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
        set {
            guard let newValue = newValue, let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true) else {
                UserDefaults.standard.removeObject(forKey: anchorKey)
                return
            }
            UserDefaults.standard.set(data, forKey: anchorKey)
        }
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        healthStore.requestAuthorization(toShare: nil, read: typesToRead, completion: completion)
    }

    func fetchAllHealthMetrics(for session: SleepSessionV2, completion: @escaping (Bool) -> Void) {
        guard let startDate = session.primarySleepPeriod?.startDateUTC, let endDate = session.primarySleepPeriod?.endDateUTC else {
            print("[HealthMetricsManager] Error: Session is missing primary sleep period start/end dates.")
            completion(false)
            return
        }

        let group = DispatchGroup()
        var metrics: [HKQuantityTypeIdentifier: Double] = [:]

        // --- Fetch Resting Heart Rate ---
        group.enter()
        fetchAverageQuantityStatistics(for: .heartRate, unit: .count().unitDivided(by: .minute()), startDate: startDate, endDate: endDate) { value, error in
            if let value = value { metrics[.heartRate] = value }
            if let error = error { print("[HealthMetricsManager] Error fetching RHR: \(error.localizedDescription)") }
            group.leave()
        }

        // --- Fetch HRV ---
        group.enter()
        fetchAverageQuantityStatistics(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), startDate: startDate, endDate: endDate) { value, error in
            if let value = value { metrics[.heartRateVariabilitySDNN] = value }
            if let error = error { print("[HealthMetricsManager] Error fetching HRV: \(error.localizedDescription)") }
            group.leave()
        }

        // --- Fetch SpO2 ---
        group.enter()
        fetchAverageQuantityStatistics(for: .oxygenSaturation, unit: .percent(), startDate: startDate, endDate: endDate) { value, error in
            if let value = value { metrics[.oxygenSaturation] = value }
            if let error = error { print("[HealthMetricsManager] Error fetching SpO2: \(error.localizedDescription)") }
            group.leave()
        }

        // --- Fetch Respiratory Rate ---
        group.enter()
        fetchAverageQuantityStatistics(for: .respiratoryRate, unit: .count().unitDivided(by: .minute()), startDate: startDate, endDate: endDate) { value, error in
            if let value = value { metrics[.respiratoryRate] = value }
            if let error = error { print("[HealthMetricsManager] Error fetching Respiratory Rate: \(error.localizedDescription)") }
            group.leave()
        }

        group.notify(queue: .main) {
            session.managedObjectContext?.perform {
                session.averageHeartRate = metrics[.heartRate] ?? 0
                session.averageHRV = metrics[.heartRateVariabilitySDNN] ?? 0
                session.averageSpO2 = metrics[.oxygenSaturation] ?? 0
                session.averageRespiratoryRate = metrics[.respiratoryRate] ?? 0
                completion(true)
            }
        }
    }

    private func fetchAverageQuantityStatistics(for quantityTypeIdentifier: HKQuantityTypeIdentifier, unit: HKUnit, startDate: Date, endDate: Date, completion: @escaping (Double?, Error?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: quantityTypeIdentifier) else {
            completion(nil, NSError(domain: "HealthMetricsManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid quantity type identifier: \(quantityTypeIdentifier.rawValue)"]))
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, error in
            guard let result = result, let average = result.averageQuantity() else {
                completion(nil, error)
                return
            }
            completion(average.doubleValue(for: unit), nil)
        }
        healthStore.execute(query)
    }

    func fetchNewWristTemperatureData(context: NSManagedObjectContext, completion: @escaping (Error?) -> Void) {
        requestAuthorization { [weak self] success, error in
            guard let self = self, success else {
                completion(error)
                return
            }

            var predicate: NSPredicate? = nil
            if self.anchor == nil {
                // If no anchor exists, fetch the last 180 days of data.
                let calendar = Calendar.current
                let endDate = Date()
                guard let startDate = calendar.date(byAdding: .day, value: -180, to: endDate) else {
                    completion(NSError(domain: "HealthMetricsManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to calculate start date for historical fetch."]))
                    return
                }
                predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            }

            let query = HKAnchoredObjectQuery(
                type: self.wristTemperatureType,
                predicate: predicate,
                anchor: self.anchor,
                limit: HKObjectQueryNoLimit
            ) { query, samples, deletedObjects, newAnchor, error in
                if let error = error {
                    completion(error)
                    return
                }

                self.anchor = newAnchor

                context.perform {
                    if let deletedObjects = deletedObjects {
                        self.deleteWristTemperatureData(with: deletedObjects, in: context)
                    }

                    if let samples = samples as? [HKQuantitySample] {
                        self.saveWristTemperatureData(with: samples, in: context)
                    }

                    do {
                        try context.save()
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            }
            self.healthStore.execute(query)
        }
    }

    private func saveWristTemperatureData(with samples: [HKQuantitySample], in context: NSManagedObjectContext) {
        for sample in samples {
            let temp = WristTemperature(context: context)
            temp.uuid = sample.uuid
            temp.date = sample.startDate
            temp.value = sample.quantity.doubleValue(for: .degreeCelsius())
            temp.isResolved = false
        }
    }

    private func deleteWristTemperatureData(with deletedObjects: [HKDeletedObject], in context: NSManagedObjectContext) {
        let request: NSFetchRequest<WristTemperature> = WristTemperature.fetchRequest()
        let uuids = deletedObjects.map { $0.uuid }
        request.predicate = NSPredicate(format: "uuid IN %@", uuids)

        do {
            let objectsToDelete = try context.fetch(request)
            for object in objectsToDelete {
                context.delete(object)
            }
        } catch {
            print("Error deleting wrist temperature data: \(error)")
        }
    }

    func resetWristTemperatureAnchor() {
        UserDefaults.standard.removeObject(forKey: anchorKey)
        print("Wrist temperature anchor has been reset.")
    }
}
