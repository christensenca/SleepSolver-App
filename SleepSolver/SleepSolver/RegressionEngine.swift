import Foundation

// Core regression engine for multiple linear regression analysis
class RegressionEngine {

    // Result structure for regression analysis
    struct RegressionResult {
        let coefficient: Double
        let standardError: Double
        let tStatistic: Double
        let pValue: Double
        let confidenceInterval: (lower: Double, upper: Double)
    }

    // Perform multiple linear regression
    static func performRegression(
        dependent: [Double],     // Y: sleep metric values
        independents: [[Double]] // X: health metrics matrix
    ) -> [RegressionResult] {
        guard !dependent.isEmpty,
              !independents.isEmpty,
              independents[0].count == dependent.count else {
            return []
        }

        let n = dependent.count
        let p = independents.count // number of predictors

        // Add intercept column (column of 1s)
        var X = independents
        X.insert(Array(repeating: 1.0, count: n), at: 0)

        // Convert to matrices
        let XMatrix = Matrix(rows: n, columns: p + 1, data: X.flatMap { $0 })
        let yVector = Matrix(rows: n, columns: 1, data: dependent)

        // Calculate (X^T * X)^(-1) * X^T * y
        guard let coefficients = solveNormalEquations(X: XMatrix, y: yVector) else {
            return []
        }

        // Calculate residuals and standard errors
        guard let yPredicted = XMatrix.multiply(by: coefficients) else {
            return []
        }
        let residuals = yVector.subtract(yPredicted)

        let residualSumSquares = residuals.sumOfSquares
        let degreesOfFreedom = Double(n - p - 1)
        let residualVariance = residualSumSquares / degreesOfFreedom

        // Calculate (X^T * X)^(-1) for standard errors
        guard let XtXInverse = calculateXtXInverse(X: XMatrix) else {
            return []
        }

        var results: [RegressionResult] = []

        for i in 0...p {
            let coefficient = coefficients[i, 0]
            let variance = XtXInverse[i, i] * residualVariance
            let standardError = sqrt(variance)
            let tStatistic = coefficient / standardError
            let pValue = calculatePValue(tStatistic: tStatistic, df: degreesOfFreedom)

            // 95% confidence interval
            let tCritical = 1.96 // Approximate for large n
            let marginOfError = tCritical * standardError
            let confidenceInterval = (
                lower: coefficient - marginOfError,
                upper: coefficient + marginOfError
            )

            results.append(RegressionResult(
                coefficient: coefficient,
                standardError: standardError,
                tStatistic: tStatistic,
                pValue: pValue,
                confidenceInterval: confidenceInterval
            ))
        }

        return results
    }

    // Solve normal equations: (X^T * X) * β = X^T * y
    private static func solveNormalEquations(X: Matrix, y: Matrix) -> Matrix? {
        // Calculate X^T * X
        guard let Xt = X.transpose(),
              let XtX = Xt.multiply(by: X) else {
            return nil
        }

        // Calculate X^T * y
        guard let Xty = Xt.multiply(by: y) else {
            return nil
        }

        // Solve for β
        return XtX.inverse()?.multiply(by: Xty)
    }

    // Calculate (X^T * X)^(-1) for standard errors
    private static func calculateXtXInverse(X: Matrix) -> Matrix? {
        guard let Xt = X.transpose(),
              let XtX = Xt.multiply(by: X) else {
            return nil
        }
        return XtX.inverse()
    }

    // Calculate p-value from t-statistic
    private static func calculatePValue(tStatistic: Double, df: Double) -> Double {
        // Use approximation for t-distribution p-value
        // For large df, t-distribution approaches normal
        if df > 30 {
            return 2 * (1 - normalCDF(abs(tStatistic)))
        } else {
            // Simplified t-distribution approximation
            let t = abs(tStatistic)
            let p = 1.0 / (1.0 + 0.2316419 * t)
            let b1 = 0.319381530
            let b2 = -0.356563782
            let b3 = 1.781477937
            let b4 = -1.821255978
            let b5 = 1.330274429

            let approximation = 1 - normalCDF(t) * (b1*p + b2*pow(p,2) + b3*pow(p,3) + b4*pow(p,4) + b5*pow(p,5))
            return 2 * (1 - approximation)
        }
    }

    // Standard normal cumulative distribution function
    private static func normalCDF(_ x: Double) -> Double {
        let a1 =  0.254829592
        let a2 = -0.284496736
        let a3 =  1.421413741
        let a4 = -1.453152027
        let a5 =  1.061405429
        let p  =  0.3275911

        let sign = x < 0 ? -1.0 : 1.0
        let absX = abs(x) / sqrt(2.0)

        let t = 1.0 / (1.0 + p * absX)
        let erf = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-absX * absX)

        return 0.5 * (1.0 + sign * erf)
    }
}

// Simple matrix class for regression calculations
class Matrix {
    let rows: Int
    let columns: Int
    var data: [Double]

    init(rows: Int, columns: Int, data: [Double]) {
        self.rows = rows
        self.columns = columns
        self.data = data
    }

    subscript(row: Int, column: Int) -> Double {
        get {
            return data[row * columns + column]
        }
        set {
            data[row * columns + column] = newValue
        }
    }

    func transpose() -> Matrix? {
        var transposedData = [Double](repeating: 0, count: rows * columns)

        for i in 0..<rows {
            for j in 0..<columns {
                transposedData[j * rows + i] = data[i * columns + j]
            }
        }

        return Matrix(rows: columns, columns: rows, data: transposedData)
    }

    func multiply(by other: Matrix) -> Matrix? {
        guard columns == other.rows else { return nil }

        var resultData = [Double](repeating: 0, count: rows * other.columns)

        for i in 0..<rows {
            for j in 0..<other.columns {
                var sum = 0.0
                for k in 0..<columns {
                    sum += data[i * columns + k] * other[k, j]
                }
                resultData[i * other.columns + j] = sum
            }
        }

        return Matrix(rows: rows, columns: other.columns, data: resultData)
    }

    func subtract(_ other: Matrix) -> Matrix {
        var resultData = [Double](repeating: 0, count: data.count)
        for i in 0..<data.count {
            resultData[i] = data[i] - other.data[i]
        }
        return Matrix(rows: rows, columns: columns, data: resultData)
    }

    func inverse() -> Matrix? {
        // Gaussian elimination for matrix inversion
        // This is a simplified implementation - for production, consider using Accelerate framework
        guard rows == columns else { return nil }

        let n = rows
        var augmented = [[Double]](repeating: [Double](repeating: 0, count: 2 * n), count: n)

        // Create augmented matrix [A | I]
        for i in 0..<n {
            for j in 0..<n {
                augmented[i][j] = data[i * n + j]
            }
            augmented[i][n + i] = 1.0
        }

        // Gaussian elimination
        for i in 0..<n {
            // Find pivot
            var maxRow = i
            for k in (i + 1)..<n {
                if abs(augmented[k][i]) > abs(augmented[maxRow][i]) {
                    maxRow = k
                }
            }

            // Swap rows
            let temp = augmented[i]
            augmented[i] = augmented[maxRow]
            augmented[maxRow] = temp

            // Make diagonal element 1
            let pivot = augmented[i][i]
            if abs(pivot) < 1e-10 { return nil } // Singular matrix

            for j in 0..<(2 * n) {
                augmented[i][j] /= pivot
            }

            // Eliminate other rows
            for k in 0..<n {
                if k != i {
                    let factor = augmented[k][i]
                    for j in 0..<(2 * n) {
                        augmented[k][j] -= factor * augmented[i][j]
                    }
                }
            }
        }

        // Extract inverse from augmented matrix
        var inverseData = [Double](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in 0..<n {
                inverseData[i * n + j] = augmented[i][n + j]
            }
        }

        return Matrix(rows: n, columns: n, data: inverseData)
    }

    var sumOfSquares: Double {
        return data.reduce(0) { $0 + $1 * $1 }
    }
}
