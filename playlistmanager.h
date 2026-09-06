#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

// ── PlaylistManager ───────────────────────────────────────────────────────
// Handles creation of XSPF (XML Shareable Playlist Format, version 1)
// playlist files.
//
// Playlists are stored in:
//   <AppConfigLocation>/playlists/<name>.xml
//
// Track locations are written as a volume-anchored pair — <location> holds a
// path relative to the containing volume's root, <volume> holds that volume's
// label (via VolumePath, see volumepath.h) — so playlists stay portable across
// drive-letter reassignment and across platforms (Windows/Linux), not just
// drive-letter changes. <volume> is omitted when the volume has no label.
//
// Instantiated in Main.qml:  PlaylistManager { id: playlistManager }
class PlaylistManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit PlaylistManager(QObject *parent = nullptr);

    // Returns the absolute path to the playlist directory (created on demand).
    Q_INVOKABLE QString playlistDirectory() const;

    // Returns true when a playlist with this name already exists.
    Q_INVOKABLE bool playlistExists(const QString &name) const;

    // Returns all playlists found in playlistDirectory(), sorted by display
    // name ascending (case-insensitive). Each element is a QVariantMap:
    //   { fileName, displayName }
    // fileName includes ".xml"; displayName has the extension stripped.
    Q_INVOKABLE QVariantList listPlaylists() const;

    // Creates a new XSPF playlist.
    // name   – file name without extension (leading/trailing whitespace trimmed)
    // tracks – QVariantList of maps, each containing at minimum:
    //            filePath (string), title (string), artist (string),
    //            album (string), number (string/int), durationMs (int/qint64)
    //
    // Returns an empty string on success, or a human-readable error message.
    Q_INVOKABLE QString createPlaylist(const QString &name,
                                       const QVariantList &tracks);

    // Appends one track to an existing playlist file.
    // nameWithExt – file name including .xml extension (e.g. "GothicRock01.xml")
    // track       – map with at least: filePath, title, artist/albumArtist, album,
    //               number or trackNumber (int), durationMs (qint64)
    // Returns true on success.
    Q_INVOKABLE bool appendTrack(const QString &nameWithExt,
                                  const QVariantMap &track);

    // Removes the first track whose <location> matches filePath from the playlist.
    // Returns true when a track was found and removed.
    Q_INVOKABLE bool removeTrackByPath(const QString &nameWithExt,
                                        const QString &filePath);

    // Rewrites the entire playlist with the given track list.
    // nameWithExt – file name including .xml extension.
    // tracks      – QVariantList in the same format as createPlaylist / trackList().
    // Returns true on success.  Use this after any reorder operation.
    Q_INVOKABLE bool rewritePlaylist(const QString &nameWithExt,
                                      const QVariantList &tracks);

    // Loads an XSPF playlist file (accepts both a local path and a file:// URL).
    // For each <track>, resolves the stored <volume>/<location> pair back to an
    // absolute path via VolumePath::resolve() (tries the named volume first,
    // then falls back to probing every mounted volume) -- this already checks
    // the file actually exists on disk (see volumepath.cpp), so a track whose
    // file is missing/deleted/moved is what ends up in "missing" below. Never
    // rewrites the playlist file itself.
    //
    // Returns a QVariantMap with:
    //   "fileName" – QString  base name + ".xml" (e.g. "GothicRock01.xml")
    //   "tracks"   – QVariantList of resolved track maps suitable for
    //                PlaybackEngine.addTracks();
    //              each map contains: filePath, title, artist, albumArtist,
    //                                 album, number, trackNumber, durationMs
    //   "missing"  – QVariantList of tracks whose file could not be found,
    //                sourced entirely from what's stored in the XSPF itself
    //                (the file can't be re-read): each map contains
    //                artist, album, title, location. See UC-10/UC-22.
    Q_INVOKABLE QVariantMap loadPlaylist(const QString &filePath);

    // Deletes a playlist file from disk.
    // nameWithExt – file name including .xml extension.
    // Returns true on success.
    Q_INVOKABLE bool deletePlaylist(const QString &nameWithExt);

private:
    QByteArray buildXspf(const QString &title,
                          const QVariantList &tracks) const;
};
