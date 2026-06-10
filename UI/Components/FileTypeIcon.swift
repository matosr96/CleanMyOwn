//
//  FileTypeIcon.swift
//  CleanMyOwn
//
//  Símbolo SF por tipo de archivo — las listas de archivos dejan de ser un
//  muro de "doc.fill" idénticos y se escanean con la vista.
//

import Foundation

enum FileTypeIcon {
    /// SF Symbol para una URL según extensión / si es directorio.
    static func symbol(for url: URL, isDirectory: Bool) -> String {
        if isDirectory {
            return url.pathExtension.lowercased() == "app" ? "app.fill" : "folder.fill"
        }
        switch url.pathExtension.lowercased() {
        case "zip", "gz", "tar", "bz2", "xz", "7z", "rar":
            return "doc.zipper"
        case "dmg", "iso", "pkg":
            return "opticaldiscdrive.fill"
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac", "aac", "ogg":
            return "music.note"
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "raw", "svg":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "log", "txt", "md":
            return "doc.text.fill"
        case "db", "sqlite", "sqlite3", "realm":
            return "cylinder.split.1x2.fill"
        case "ipa", "xcarchive", "xcworkspace", "xcodeproj":
            return "hammer.fill"
        case "vdi", "vmdk", "qcow2", "utm", "pvm":
            return "server.rack"
        default:
            return "doc.fill"
        }
    }
}
