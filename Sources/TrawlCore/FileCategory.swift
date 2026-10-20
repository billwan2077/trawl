import Foundation

/// Common file types, identified by file extension.
public enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case word, excel, powerpoint, pdf, text, log, image, video, audio, archive

    public var id: String { rawValue }

    /// The preset offered as "Common Files".
    public static let common: Set<FileCategory> = [.word, .excel, .powerpoint, .pdf, .text, .log, .image, .video]

    public var title: String {
        switch self {
        case .word: "Word"
        case .excel: "Excel"
        case .powerpoint: "PowerPoint"
        case .pdf: "PDF"
        case .text: "Text"
        case .log: "Log"
        case .image: "Images"
        case .video: "Video"
        case .audio: "Audio"
        case .archive: "Archives"
        }
    }

    /// Lower-case extensions, most typical first (the first one is used to look up the icon).
    public var extensions: [String] {
        switch self {
        case .word: ["docx", "doc", "docm", "dotx", "dot", "rtf", "odt", "pages"]
        case .excel: ["xlsx", "xls", "xlsm", "xlsb", "xltx", "csv", "ods", "numbers"]
        case .powerpoint: ["pptx", "ppt", "pptm", "ppsx", "pps", "potx", "odp", "key"]
        case .pdf: ["pdf"]
        case .text: ["txt", "text", "md", "markdown", "json", "xml", "yaml", "yml", "ini", "cfg", "conf"]
        case .log: ["log"]
        case .image: ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "svg",
                      "psd", "ico", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf"]
        case .video: ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "mts"]
        case .audio: ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "wma", "opus"]
        case .archive: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "iso"]
        }
    }

    private static let byExtension: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        for category in allCases {
            for ext in category.extensions { map[ext] = category }
        }
        return map
    }()

    public init?(fileExtension ext: String) {
        guard let category = Self.byExtension[ext.lowercased()] else { return nil }
        self = category
    }

    public init?(url: URL) {
        self.init(fileExtension: url.pathExtension)
    }
}
