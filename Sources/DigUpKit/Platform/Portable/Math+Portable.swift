// Vector math without Accelerate (Linux, Windows): plain loops over SIMD8 lanes. 70,000 vectors score in a few
// milliseconds either way; `Float16` is a hardware type on x86-64 and arm64 here (it's only missing on Intel Macs).
#if !canImport(Accelerate)
extension Vectors {
    /// Converts `count` float16s into float32s with SIMD acceleration.
    static func floats(fromHalf source: UnsafePointer<Float16>, count: Int, to destination: UnsafeMutablePointer<Float>) {
        let simdCount = count / 8
        for chunk in 0..<simdCount {
            let offset = chunk * 8
            let vector = SIMD8<Float>(
                Float(source[offset]),
                Float(source[offset + 1]),
                Float(source[offset + 2]),
                Float(source[offset + 3]),
                Float(source[offset + 4]),
                Float(source[offset + 5]),
                Float(source[offset + 6]),
                Float(source[offset + 7])
            )
            UnsafeMutableRawPointer(destination + offset).storeBytes(of: vector, as: SIMD8<Float>.self)
        }
        for index in (simdCount * 8)..<count {
            destination[index] = Float(source[index])
        }
    }

    /// `scores[i]` = the dot product of row `i` of `rows` (`count` rows of `dimension` floats) with `query`.
    static func scores(of rows: UnsafePointer<Float>, count: Int, query: UnsafePointer<Float>,
                       into scores: UnsafeMutablePointer<Float>) {
        let lanes = dimension / 8   // 768 = 96 × 8
        withUnsafeTemporaryAllocation(of: SIMD8<Float>.self, capacity: lanes) { queryLanes in
            let queryRaw = UnsafeRawPointer(query)
            for lane in 0..<lanes {
                queryLanes[lane] = queryRaw.loadUnaligned(fromByteOffset: lane * 32, as: SIMD8<Float>.self)
            }
            for row in 0..<count {
                let start = UnsafeRawPointer(rows + row * dimension)
                var sum = SIMD8<Float>.zero
                for lane in 0..<lanes {
                    sum += queryLanes[lane] * start.loadUnaligned(fromByteOffset: lane * 32, as: SIMD8<Float>.self)
                }
                scores[row] = sum.sum()
            }
        }
    }
}
#endif
