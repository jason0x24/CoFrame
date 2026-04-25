import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 64, height: 64)
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .frame(width: 26, height: 26)
                    } else {
                        Circle()
                            .frame(width: 52, height: 52)
                    }
                }
                .foregroundStyle(Color.red)
                .animation(.easeInOut(duration: 0.18), value: isRecording)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
    }
}
