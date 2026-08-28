import SwiftUI

struct SongCell: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore

    let song: Song
    var showCover = true
    /// 玻璃行模式：为行添加清透液态玻璃底（二级列表页统一风格用）
    var glassRow = false
    var onTap: (() -> Void)?

    @State private var showAddToPlaylist = false
    @State private var appeared = false

    private var isCurrent: Bool {
        player.currentSong?.identityKey == song.identityKey
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if showCover {
                CoverImage(url: song.coverURL, size: 46, cornerRadius: 10)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(song.name)
                        .font(BeansFont.appFont(15, isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.beansAmber : Color.beansLabel)
                        .lineLimit(1)
                    if song.isVIP {
                        Text("VIP")
                            .font(BeansFont.appFont(9, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color(red: 0.93, green: 0.25, blue: 0.22)))
                    }
                }
                Text(song.artists.isEmpty ? song.album : song.artists)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isCurrent && player.isPlaying {
                NowPlayingIndicator()
            } else {
                Text(song.formattedDuration)
                    .font(BeansFont.appFont(12, .regular, .monospaced))
                    .foregroundStyle(Color.beansComment)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .scaleEffect(isCurrent ? 1.012 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isCurrent)
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            Button {
                player.playNext(song)
            } label: {
                Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                showAddToPlaylist = true
            } label: {
                Label("添加到歌单", systemImage: "text.badge.plus")
            }
            if !isCurrent {
                Button {
                    if let index = player.queue.firstIndex(of: song) {
                        player.playQueueIndex(index)
                    }
                } label: {
                    Label("立即播放", systemImage: "play.fill")
                }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
                .environmentObject(auth)
        }
    }

    var body: some View {
        let _ = theme.accent
        Group {
            if glassRow {
                rowContent
                    .padding(.horizontal, 10)
                    .background {
                                            BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
            } else {
                rowContent
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.28), value: appeared)
        .onAppear { appeared = true }
    }
}
