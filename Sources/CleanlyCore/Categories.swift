import Foundation

public struct CategoryCatalog: Sendable {
  public static let builtIn: [String: [String]] = [
    "Images": words(
      "jpg jpeg png gif bmp tiff tif webp svg ico heic heif avif raw cr2 cr3 nef arw orf rw2 dng psd psb ai eps cdr xcf sketch fig jfif pjpeg pjp apng cur ani tga exr hdr jp2 j2k jpf jpx jpm mj2 wbmp xbm xpm pgm ppm pbm pnm pcx pic pict sgi ilbm lbm iff"
    ),
    "Audio": words(
      "mp3 wav flac aac ogg oga opus m4a wma aiff aif aifc alac ape mpc mp2 ac3 dts amr awb ra rm mid midi kar xmf mxmf rtttl rtx ota spx gsm 8svx caf au snd tta voc vox w64 wv dsf dff dsd mka s3m xm it mod"
    ),
    "Video": words(
      "mp4 mkv avi mov wmv flv webm m4v mpg mpeg m2v m2ts mts ts vob ogv 3gp 3g2 f4v f4p f4a f4b rmvb asf divx xvid hevc h264 h265 mxf roq nsv yuv dv gxf m1v m4b tod tp trp rec"
    ),
    "Documents": words(
      "pdf doc docx odt rtf txt md markdown rst tex xls xlsx ods csv tsv ppt pptx odp key pages numbers wpd wps abw zabw sdw sxw dot dotx docm xlsm xlsb xltx xlt pptm potx pot pub xps oxps epub mobi azw azw3 djvu djv cbz cbr fb2 lit pdb lrf snb tcr tr2 tr3"
    ),
    "Archives": words(
      "zip rar 7z tar gz bz2 xz tgz tbz2 txz tar.gz tar.bz2 tar.xz lz lzma lz4 zst zstd br brotli cab iso bin z arc pak pea zz ace arj lha lzh zoo sit sitx hqx jar war ear aar whl egg"
    ),
    "Applications": words(
      "app dmg pkg ipa apk exe msi appimage snap flatpak xpi crx appx appxbundle msix msixbundle"),
    "Code": words(
      "swift go c h cpp cxx cc hpp m mm rs py pyw rb php java kt kts scala js jsx mjs cjs ts tsx vue svelte html htm css scss sass less sh bash zsh fish ps1 bat cmd lua pl pm r rmd dart ex exs erl hrl fs fsx fsi clj cljs cljc hs lhs ml mli groovy gradle make cmake mk dockerfile tf tfvars asm s sol ino ipynb"
    ),
    "Data": words(
      "json xml yaml yml toml ini cfg conf config env properties plist xmp rss atom geojson gpx kml kmz gml shp dbf sql sqlite sqlite3 db db3 mdb accdb fdb sdb ndf mdf ldf bak dump parquet avro orc feather arrow hdf5 h5 nc mat sav dta sas7bdat rds rda rdata xsd dtd wsdl graphql gql proto thrift capnp flatbuffers msgpack cbor bson ndjson jsonl jsonc json5 har vcf vcard ics ical ifb ldif dsv psv"
    ),
    "Fonts": words("ttf otf woff woff2 eot fon fnt"),
    "Design": words("blend fbx obj stl 3ds dae glb gltf usd usdz step stp dwg dxf cad"),
    "Torrents": words("torrent magnet"),
    "Books": words("epub mobi azw azw3 fb2 cbr cbz"),
    "Disk Images": words("dmg iso img sparseimage sparsebundle toast vhd vhdx vmdk qcow qcow2"),
  ]

  public let categories: [String: [String]]
  private let extensionIndex: [String: String]

  public init(settings: CleanlySettings) {
    let disabled = Set(settings.disabledCategories.map { $0.lowercased() })
    var merged = Self.builtIn.filter { !disabled.contains($0.key.lowercased()) }
    for (name, extensions) in settings.customCategories {
      let normalized = extensions.map(Self.normalizeExtension).filter { !$0.isEmpty }
      if !normalized.isEmpty { merged[name] = normalized }
    }
    categories = merged

    var index: [String: String] = [:]
    let priority = [
      "Images", "Audio", "Video", "Documents", "Archives", "Applications", "Code", "Data", "Fonts",
      "Design", "Torrents", "Books", "Disk Images",
    ]
    for name in priority where merged[name] != nil {
      for ext in merged[name, default: []] { index[Self.normalizeExtension(ext)] = name }
    }
    // User categories intentionally take precedence over built-ins.
    for name in settings.customCategories.keys.sorted() {
      for ext in settings.customCategories[name, default: []] {
        index[Self.normalizeExtension(ext)] = name
      }
    }
    extensionIndex = index
  }

  public func category(for url: URL, isDirectory: Bool) -> String {
    if isDirectory { return "Folders" }
    let lower = url.lastPathComponent.lowercased()
    let candidates = extensionIndex.keys
      .filter { lower.hasSuffix(".\($0)") }
      .sorted { $0.count > $1.count }
    if let match = candidates.first, let category = extensionIndex[match] { return category }
    if lower == "dockerfile" || lower == "makefile" { return "Code" }
    return "Other"
  }

  public static func normalizeExtension(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
      .lowercased()
  }

  private static func words(_ value: String) -> [String] {
    value.split(separator: " ").map(String.init)
  }
}
