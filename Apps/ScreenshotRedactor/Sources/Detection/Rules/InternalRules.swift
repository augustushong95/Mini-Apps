import Darwin
import Foundation

/// IP addresses and internal hostnames.
nonisolated enum InternalRules {
    // MARK: IPv4

    /// Four dotted numbers, with an optional CIDR suffix or port. Not when
    /// glued to letters ("v1.2.3.4") or to more dotted numbers ("1.2.3.4.5").
    private static let ipv4 = Pattern(#"(?<![0-9A-Za-z.])((?:\d{1,3}\.){3}\d{1,3})(?:/\d{1,2}|:\d{1,5})?(?![0-9A-Za-z]|\.\d)"#)
    private static let versionContext = Pattern(#"(?i)(?:\bv|version|ver\.?|build|release|rev)\s*$"#)
    private static let harmlessIPv4: Set<String> = ["0.0.0.0", "127.0.0.1", "255.255.255.255"]

    static func ipv4Matches(in line: String) -> [TextMatch] {
        ipv4.matches(in: line).compactMap { result in
            guard let range = line.range(result.range), let addressRange = line.range(result.range(at: 1)) else { return nil }
            let address = String(line[addressRange])
            guard isValidIPv4(address), !harmlessIPv4.contains(address) else { return nil }
            let before = String(line[line.startIndex..<range.lowerBound])
            if versionContext.firstMatch(in: before) != nil { return nil }
            return TextMatch(range: range, label: "IP address", category: .internalInfo, detector: .ipAddresses)
        }
    }

    static func isValidIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            // "01.02.03.04" reads as a date or version, not an address.
            guard !part.isEmpty, part.count <= 3, part == "0" || !part.hasPrefix("0"),
                  let value = Int(part), (0...255).contains(value)
            else { return false }
        }
        var address = in_addr()
        return inet_pton(AF_INET, text, &address) == 1
    }

    // MARK: IPv6

    private static let ipv6 = Pattern(#"(?<![0-9A-Za-z:.])((?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4})(%[A-Za-z0-9]+)?(?:/\d{1,3})?(?![0-9A-Za-z:])"#)

    static func ipv6Matches(in line: String) -> [TextMatch] {
        ipv6.matches(in: line).compactMap { result in
            guard let range = line.range(result.range), let addressRange = line.range(result.range(at: 1)) else { return nil }
            guard isMeaningfulIPv6(String(line[addressRange])) else { return nil }
            return TextMatch(range: range, label: "IP address", category: .internalInfo, detector: .ipAddresses)
        }
    }

    /// A valid IPv6 address with enough content to be one: not "::1", and
    /// not two short groups like "a::b". Times and MAC addresses never parse.
    static func isMeaningfulIPv6(_ text: String) -> Bool {
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return false }
        let groups = text.split(separator: ":", omittingEmptySubsequences: true)
        let hexDigits = groups.reduce(0) { $0 + $1.count }
        if text == "::1" || text == "::" { return false }
        if groups.count >= 3 { return hexDigits >= 4 }
        return text.contains("::") && groups.count >= 2 && hexDigits >= 5
    }

    // MARK: Hostnames

    private static let hostname = Pattern(#"(?<![A-Za-z0-9\-.])((?:[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z][A-Za-z0-9\-]{0,61})(?::\d{1,5})?(?![A-Za-z0-9\-]|\.[A-Za-z0-9])"#)

    /// Endings used only on private networks.
    private static let internalSuffixes: [String] = [
        ".internal", ".local", ".lan", ".corp", ".intranet", ".localdomain", ".private", ".home.arpa", ".intra", ".priv",
    ]
    /// Labels that mark a private part of a public domain ("build.corp.example.com").
    private static let internalLabels: Set<String> = ["corp", "internal", "intra", "intranet", "priv", "private", "lan"]
    /// Common file extensions, so "config.internal.json" isn't a host.
    private static let fileExtensions: Set<String> = [
        "json", "yml", "yaml", "toml", "xml", "plist", "txt", "md", "log", "swift", "js", "ts", "tsx", "jsx", "py",
        "rb", "go", "rs", "java", "kt", "c", "h", "m", "cpp", "cs", "php", "html", "css", "scss", "sh", "zsh",
        "png", "jpg", "jpeg", "gif", "pdf", "zip", "env", "ini", "conf", "cfg", "lock", "sql", "csv",
    ]

    static func hostnameMatches(in line: String) -> [TextMatch] {
        hostname.matches(in: line).compactMap { result in
            guard let range = line.range(result.range), let hostRange = line.range(result.range(at: 1)) else { return nil }
            guard isInternalHostname(String(line[hostRange])) else { return nil }
            return TextMatch(range: range, label: "Internal hostname", category: .internalInfo, detector: .internalHosts)
        }
    }

    static func isInternalHostname(_ host: String) -> Bool {
        let lower = host.lowercased()
        let labels = lower.split(separator: ".").map(String.init)
        guard labels.count >= 2, let last = labels.last else { return false }
        if fileExtensions.contains(last) { return false }
        if internalSuffixes.contains(where: { lower.hasSuffix($0) }) { return true }
        return labels.dropLast().contains(where: internalLabels.contains)
    }
}
