import Foundation

enum DiffLineKind { case same, added, removed }

struct DiffLine {
    var kind: DiffLineKind
    var primaryIndex: Int?    // 0-based line index in primary
    var secondaryIndex: Int?  // 0-based line index in secondary
}

private let diffCharacterLimit = 500_000

/// Returns nil if files are too large to diff.
func computeLineDiff(primary: String, secondary: String) -> [DiffLine]? {
    guard primary.count + secondary.count <= diffCharacterLimit else { return nil }

    let a = primary.components(separatedBy: "\n")
    let b = secondary.components(separatedBy: "\n")
    let lcs = myersLCS(a, b)

    var result: [DiffLine] = []
    var ai = 0, bi = 0
    for (la, lb) in lcs {
        while ai < la {
            result.append(DiffLine(kind: .removed, primaryIndex: ai, secondaryIndex: nil))
            ai += 1
        }
        while bi < lb {
            result.append(DiffLine(kind: .added, primaryIndex: nil, secondaryIndex: bi))
            bi += 1
        }
        result.append(DiffLine(kind: .same, primaryIndex: ai, secondaryIndex: bi))
        ai += 1; bi += 1
    }
    while ai < a.count {
        result.append(DiffLine(kind: .removed, primaryIndex: ai, secondaryIndex: nil))
        ai += 1
    }
    while bi < b.count {
        result.append(DiffLine(kind: .added, primaryIndex: nil, secondaryIndex: bi))
        bi += 1
    }
    return result
}

// Myers O(ND) LCS — returns matching pairs (indexInA, indexInB)
private func myersLCS(_ a: [String], _ b: [String]) -> [(Int, Int)] {
    let n = a.count, m = b.count
    guard n > 0, m > 0 else { return [] }

    let max = n + m
    var v = [Int](repeating: 0, count: 2 * max + 1)
    var trace: [[Int]] = []

    outer: for d in 0...max {
        trace.append(v)
        for k in stride(from: -d, through: d, by: 2) {
            let ki = k + max
            var x: Int
            if k == -d || (k != d && v[ki - 1] < v[ki + 1]) {
                x = v[ki + 1]
            } else {
                x = v[ki - 1] + 1
            }
            var y = x - k
            while x < n && y < m && a[x] == b[y] { x += 1; y += 1 }
            v[ki] = x
            if x >= n && y >= m { break outer }
        }
    }

    // Backtrack to extract LCS pairs
    var matches: [(Int, Int)] = []
    var x = n, y = m
    for d in stride(from: trace.count - 1, through: 1, by: -1) {
        let vp = trace[d - 1]
        let k = x - y
        let ki = k + max
        var prevK: Int
        if k == -d || (k != d && vp[ki - 1] < vp[ki + 1]) {
            prevK = k + 1
        } else {
            prevK = k - 1
        }
        let prevX = vp[prevK + max]
        let prevY = prevX - prevK
        // Diagonal (snake) from (prevX,prevY) to wherever it ends before the edit
        var sx = prevX, sy = prevY
        while sx < n && sy < m && a[sx] == b[sy] { sx += 1; sy += 1 }
        for i in 0..<(sx - prevX) {
            matches.append((prevX + i, prevY + i))
        }
        x = prevX; y = prevY
    }
    // Handle d==0 diagonal
    var sx = 0, sy = 0
    while sx < n && sy < m && a[sx] == b[sy] { sx += 1; sy += 1 }
    for i in 0..<sx { matches.append((i, i)) }

    return matches.sorted { $0.0 < $1.0 }
}
