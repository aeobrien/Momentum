import SwiftUI

struct TimeSelectionView: View {
    @State private var selectedTime: Date = Date()
    @State private var availableTime: TimeInterval?

    var body: some View {
        VStack {
            Text("Select the time you want to be done by:")
                .font(.headline)
                .padding()

            DatePicker("Done by", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(WheelDatePickerStyle())
                .padding()

            Button(action: {
                calculateAvailableTime()
            }) {
                Text("Calculate Available Time")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding()

            if let time = availableTime {
                Text("You have \(Int(time / 60)) minutes available.")
                    .padding()
            }
        }
        .padding()
    }

    private func calculateAvailableTime() {
        let currentTime = Date()
        if selectedTime > currentTime {
            availableTime = selectedTime.timeIntervalSince(currentTime)
        } else {
            availableTime = nil
        }
    }
}

struct TimeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        TimeSelectionView()
    }
}
