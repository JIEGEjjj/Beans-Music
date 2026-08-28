import SwiftUI

// MARK: - 歌手主页（点击播放器顶部歌手名跳转：热门歌曲 + 专辑）

struct ArtistHomeSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    let artistName: String
    var artistSource: SongSource = .netease
    var artistID: String?

    init(artist: Artist) {
        self.artistName = artist.name
        self.artistSource = artist.source
        self.artistID = artist.id
    }

    init(artistName: String, artistSource: SongSource = .netease) {
        self.artistName = artistName
        self.artistSource = artistSource
        self.artistID = nil
    }

    @State private var artist: Artist?
    @State private var hotSongs: [Song] = []
    @State private var albums: [Album] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        BeansNavigationStack {
            Group {
                if loading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            artistHeader
                            hotSongsSection
                            if artistSource == .netease {
                                albumsSection
                            }
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 16)
                    }
                    .beansScrollIndicatorsHidden()
                }
            }
            .navigationTitle("歌手主页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await load() }
        .modifier(BeansSheetModifier(detents: [.large], dragIndicator: true))
    }

    private var artistHeader: some View {
        HStack(spacing: 14) {
            AsyncImage(url: artist?.coverURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.beansComment)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .background(Color.beansGlassFill, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(artist?.name ?? artistName)
                    .font(BeansFont.appFont(20, .bold))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                Text(artistSource == .netease
                     ? "热门歌曲 \(hotSongs.count) 首 · 专辑 \(albums.count) 张"
                     : "热门歌曲 \(hotSongs.count) 首")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var hotSongsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("热门歌曲")
                .font(BeansFont.appFont(17, .bold))
                .foregroundStyle(Color.beansLabel)
                .padding(.horizontal, 16)
            if !hotSongs.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        BeansHaptics.tap()
                        player.play(songs: hotSongs, startAt: 0)
                        dismiss()
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.beansAmber))
                    }
                    .buttonStyle(.plain)
                    Button {
                        BeansHaptics.tap()
                        player.play(songs: hotSongs.shuffled(), startAt: 0)
                        dismiss()
                    } label: {
                        Label("随机播放", systemImage: "shuffle")
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(Color.beansAmber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().strokeBorder(Color.beansAmber.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
            }
            if hotSongs.isEmpty {
                Text("暂无歌曲")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(hotSongs.enumerated()), id: \.element.identityKey) { index, song in
                        Button {
                            BeansHaptics.tap()
                            player.play(songs: hotSongs, startAt: index)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(BeansFont.appFont(13, .semibold, .rounded))
                                    .foregroundStyle(index < 3 ? Color.beansAmber : Color.beansComment)
                                    .frame(width: 22)
                                CoverImage(url: song.coverURL, size: 40, cornerRadius: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.name)
                                        .font(BeansFont.appFont(14, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                        .lineLimit(1)
                                    Text(song.album)
                                        .font(BeansFont.appFont(11))
                                        .foregroundStyle(Color.beansComment)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("专辑")
                .font(BeansFont.appFont(17, .bold))
                .foregroundStyle(Color.beansLabel)
                .padding(.horizontal, 16)
            if albums.isEmpty {
                Text("暂无专辑")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
                    .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 12) {
                    ForEach(albums) { album in
                        Button {
                            playAlbum(album)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverImage(url: album.coverURL, size: 88, cornerRadius: 12)
                                    .frame(maxWidth: .infinity)
                                Text(album.name)
                                    .font(BeansFont.appFont(11, .medium))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(1)
                                if let count = album.trackCount {
                                    Text("\(count) 首")
                                        .font(BeansFont.appFont(10))
                                        .foregroundStyle(Color.beansComment)
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                                                BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func playAlbum(_ album: Album) {
        guard let id = Int(album.id.replacingOccurrences(of: "netease-", with: "")) else { return }
        BeansHaptics.tap()
        Task {
            if let songs = try? await NetEaseAPI.shared.albumSongs(albumID: id), !songs.isEmpty {
                player.play(songs: songs, startAt: 0)
                dismiss()
            } else {
                ToastCenter.shared.show("专辑歌曲加载失败", duration: 2)
            }
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        if artistSource == .qq {
            await loadQQArtist()
        } else if artistSource == .kugou {
            await loadKugouArtist()
        } else {
            await loadNetEaseArtist()
        }
    }

    private func loadNetEaseArtist() async {
        do {
            let id: Int
            if let artistID, let parsed = Int(artistID.replacingOccurrences(of: "netease-", with: "")), parsed > 0 {
                id = parsed
            } else {
                let artists = try await NetEaseAPI.shared.searchArtists(keyword: artistName, limit: 5)
                guard let first = artists.first else {
                    errorMessage = "未找到歌手「\(artistName)」"
                    loading = false
                    return
                }
                artist = first
                id = Int(first.id.replacingOccurrences(of: "netease-", with: "")) ?? 0
            }
            async let songs = (try? NetEaseAPI.shared.artistHotSongs(artistID: id)) ?? []
            async let albums = (try? NetEaseAPI.shared.artistAlbums(artistID: id)) ?? []
            let (s, a) = await (songs, albums)
            hotSongs = s
            self.albums = a
            // 接口异常时兜底：用搜索补全歌手歌曲（避免“暂无”）
            if hotSongs.isEmpty, let fallback = try? await NetEaseAPI.shared.search(keyword: artistName, limit: 30) {
                hotSongs = fallback
            }
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }

    /// QQ 歌手：优先用歌手 mid 拉热门歌曲，失败则按歌手名搜索 QQ 歌曲（保证不是网易云数据）
    private func loadQQArtist() async {
        var mid: String? = nil
        if let artistID, !artistID.hasPrefix("qq-") {
            mid = artistID
        } else if let first = (try? await QQMusicAPI.shared.searchArtists(keyword: artistName, limit: 5))?.first {
            artist = first
            mid = first.id
        }
        var songs = (try? await QQMusicAPI.shared.artistHotSongs(mid: mid, name: artistName)) ?? []
        if songs.isEmpty {
            songs = (try? await QQMusicAPI.shared.searchSongs(keyword: artistName, limit: 50)) ?? []
        }
        hotSongs = songs
        loading = false
    }

    /// 酷狗暂未提供稳定的公开歌手主页数据时，使用官方综合搜索结果兜底。
    /// 这里严格按歌手名过滤，避免把关键词搜索的其他歌手歌曲混进来。
    private func loadKugouArtist() async {
        let artists = (try? await KugouMusicAPI.shared.searchArtists(keyword: artistName, limit: 10)) ?? []
        if let first = artists.first {
            artist = first
        }
        async let exact = KugouMusicAPI.shared.searchSongs(keyword: artistName, limit: 100)
        async let hot = KugouMusicAPI.shared.searchSongs(keyword: "\(artistName) 热门", limit: 80)
        async let works = KugouMusicAPI.shared.searchSongs(keyword: "\(artistName) 歌曲", limit: 80)
        let batches = [
            (try? await exact) ?? [],
            (try? await hot) ?? [],
            (try? await works) ?? [],
        ]
        var seen = Set<String>()
        let songs = batches.flatMap { $0 }.filter { song in
            seen.insert(song.identityKey).inserted
        }
        let normalizedName = artistName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        hotSongs = songs.filter { song in
            song.artists
                .split(separator: "/")
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .contains { $0 == normalizedName || $0.contains(normalizedName) || normalizedName.contains($0) }
        }
        if hotSongs.isEmpty {
            hotSongs = songs
        }
        loading = false
    }
}
