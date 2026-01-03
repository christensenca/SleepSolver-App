import SwiftUI

struct SleepNeedSliderView: View {
    @Binding var value: Double // The current value of the slider
    var range: ClosedRange<Double> // The range of the slider (e.g., 6.0...10.0)
    var step: Double = 0.25 // The step increment

    // Colors
    let trackColor: Color = Color.purple.opacity(0.3) // Light purple
    let middleTrackColor: Color = Color.purple.opacity(0.6) // Medium purple
    let thumbColor: Color = .white
    let thumbBorderColor: Color = Color(.systemGray)

    // Dimensions
    let trackHeight: CGFloat = 20.0
    let thumbSize: CGFloat = 30.0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background Track (full width, lighter color)
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .foregroundColor(trackColor)
                    .frame(width: geometry.size.width, height: trackHeight)

                // Middle Track (darker color, representing 25th to 75th percentile of the range)
                let overallRange = range.upperBound - range.lowerBound
                let middleSectionStartValue = range.lowerBound + (overallRange * 0.25)
                let middleSectionEndValue = range.lowerBound + (overallRange * 0.75)

                let middleSectionStartX = (CGFloat((middleSectionStartValue - range.lowerBound) / overallRange) * geometry.size.width)
                let middleSectionWidth = (CGFloat((middleSectionEndValue - middleSectionStartValue) / overallRange) * geometry.size.width)
                
                if middleSectionWidth > 0 {
                    RoundedRectangle(cornerRadius: trackHeight / 2)
                        .foregroundColor(middleTrackColor)
                        .frame(width: middleSectionWidth, height: trackHeight)
                        .offset(x: middleSectionStartX)
                }


                // Thumb
                Circle()
                    .foregroundColor(thumbColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(thumbBorderColor, lineWidth: 1)
                    )
                    .shadow(radius: 2)
                    .offset(x: thumbOffset(geometry: geometry))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gestureValue in
                                updateValue(with: gestureValue, in: geometry)
                            }
                    )
            }
            // Center the ZStack vertically if the geometry reader is taller than the track
            .frame(height: geometry.size.height, alignment: .center)
        }
        .frame(height: thumbSize) // Set the overall height of the slider view
    }

    private func thumbOffset(geometry: GeometryProxy) -> CGFloat {
        let overallRange = range.upperBound - range.lowerBound
        guard overallRange > 0 else { return 0 }

        // Calculate the position of the thumb based on the current value
        let valueRatio = CGFloat((value - range.lowerBound) / overallRange)
        let trackWidth = geometry.size.width - thumbSize // Effective width for thumb movement
        
        // Clamp the offset to ensure thumb stays within track bounds
        return min(max(0, valueRatio * trackWidth), trackWidth)
    }

    private func updateValue(with gesture: DragGesture.Value, in geometry: GeometryProxy) {
        let overallRange = range.upperBound - range.lowerBound
        guard overallRange > 0 else { return }

        let trackWidth = geometry.size.width - thumbSize
        let newLocation = gesture.location.x - (thumbSize / 2) // Adjust for thumb's center
        
        var newValueRatio = newLocation / trackWidth
        newValueRatio = max(0, min(1, newValueRatio)) // Clamp between 0 and 1

        let unsteppedValue = range.lowerBound + (Double(newValueRatio) * overallRange)
        
        // Apply stepping
        let steppedValue = (unsteppedValue / step).rounded() * step
        
        // Clamp to range
        self.value = min(range.upperBound, max(range.lowerBound, steppedValue))
    }
}

struct SleepNeedSliderView_Previews: PreviewProvider {
    @State static var currentValue: Double = 7.5
    static var previews: some View {
        VStack {
            SleepNeedSliderView(value: $currentValue, range: 6.0...10.0, step: 0.25)
                .padding()
            Text("Current Value: \(currentValue, specifier: "%.2f") hours")
        }
        .padding()
    }
}
