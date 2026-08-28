import SwiftUI

struct SleepTimerSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss

    private let options = [5, 15, 30, 45, 60, 90]
    /// 自定义定时分钟数
    @State private var customMinutes = 30

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            List {
                if player.sleepTimerRemaining > 0 {
                    Section("当前定时") {
                        Label {
                            Text("剩余 \(player.sleepTimerFormatted ?? "0:00")")
                        } icon: {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundStyle(Color.beansAmber)
                        }
                    }
                }
                Section("定时关闭播放") {
                    ForEach(options, id: \.self) { minutes in
                        Button {
                            player.startSleepTimer(minutes: minutes)
                            dismiss()
                        } label: {
                            HStack {
                                Text("\(minutes) 分钟后关闭")
                                    .foregroundStyle(Color.beansLabel)
                                Spacer()
                                if isActive(minutes) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.beansAmber)
                                }
                            }
                        }
                    }
                    Button(role: .destructive) {
                        player.stopSleepTimer()
                        dismiss()
                    } label: {
                        Label("关闭定时", systemImage: "xmark.circle")
                    }
                }
                Section("自定义时长") {
                    Stepper(value: $customMinutes, in: 1...180, step: 1) {
                        HStack {
                            Text("自定义")
                            Spacer()
                            Text("\(customMinutes) 分钟")
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                    Button {
                        player.startSleepTimer(minutes: customMinutes)
                        dismiss()
                    } label: {
                        Label("\(customMinutes) 分钟后关闭", systemImage: "timer")
                            .foregroundStyle(Color.beansLabel)
                    }
                }
            }
            .navigationTitle("睡眠定时")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func isActive(_ minutes: Int) -> Bool {
        guard let end = player.sleepTimerEndsAt else { return false }
        let remaining = end.timeIntervalSinceNow
        return remaining > 0 && remaining < TimeInterval(minutes * 60) + 5
    }
}
