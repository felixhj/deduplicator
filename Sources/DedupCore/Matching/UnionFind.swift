/// Disjoint-set forest with path halving and union by size.
struct UnionFind {
    private var parent: [Int]
    private var size: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        size = Array(repeating: 1, count: count)
    }

    mutating func find(_ x: Int) -> Int {
        var x = x
        while parent[x] != x {
            parent[x] = parent[parent[x]]
            x = parent[x]
        }
        return x
    }

    mutating func union(_ a: Int, _ b: Int) {
        var ra = find(a)
        var rb = find(b)
        guard ra != rb else { return }
        if size[ra] < size[rb] { swap(&ra, &rb) }
        parent[rb] = ra
        size[ra] += size[rb]
    }

    /// Components with at least `minSize` members, each in ascending order.
    mutating func components(minSize: Int = 2) -> [[Int]] {
        var byRoot: [Int: [Int]] = [:]
        for i in parent.indices {
            byRoot[find(i), default: []].append(i)
        }
        return byRoot.values.filter { $0.count >= minSize }.sorted { $0[0] < $1[0] }
    }
}
