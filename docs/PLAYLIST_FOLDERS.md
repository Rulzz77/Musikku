# Playlist Folders

Playlist Folders adds user-owned groups to the phone Library.

## What a folder stores

A folder stores stable playlist browse IDs rather than copying songs or playlist records. It can group playlists from:

- YouTube Music account Library
- Spotify imports stored by MusikKu
- Device playlists stored by MusikKu

A playlist can belong to one folder at a time. Selecting it in another folder moves its reference there. Playlists not assigned to a folder remain in the normal Library list.

## Folder actions

From Library, create a folder, give it a name, and select the playlists it should contain. Open a folder to browse its playlist cards. Edit a folder to rename it or change membership.

Deleting a folder deletes only its folder metadata. It does not delete playlists, tracks, downloads, or files.

## Backup and restore

Backup schema v3 includes folder IDs, names, and playlist browse-ID memberships. Restore supports merge and replace:

- Merge keeps existing folder titles for matching folder IDs and combines non-duplicate memberships.
- Replace restores the folder list from the backup.
- Schema v1 and v2 backups remain readable. They do not contain folder metadata, so no folder records can be reconstructed from them.

Folder backups only preserve references. They do not include YouTube Music or Spotify credentials, remote playlist contents, downloaded audio, or local file bytes. A restored folder entry whose source playlist is unavailable can be edited or removed without affecting other data.
