import XCTest
@testable import WanderCore

final class GroupingTests: XCTestCase {
    struct FakeLookup: PlaceLookup {
        func place(for p: GeoPoint) async throws -> Place {
            if p.lat > 30 { return Place(countryCode: "JP", country: "日本", city: p.lon > 137 ? "東京" : "京都市") }
            return Place(countryCode: "TW", country: "台灣", city: "臺北市")
        }
    }

    func d(_ s: String) -> Date { MetadataReader.parseExifDate(s, offset: "+09:00")!.0 }

    func testByDateOneGroupPerLocalDay() {
        let items = [Fixtures.item("a", date: d("2026:11:02 23:30:00")), Fixtures.item("b", date: d("2026:11:03 00:30:00")),
                     Fixtures.item("c", date: d("2026:11:03 10:00:00")), Fixtures.item("x", date: nil)]
        let g = Grouping.byDate(items)
        XCTAssertEqual(g.map(\.itemIDs), [["a"], ["b", "c"], ["x"]])
        XCTAssertEqual(g.last?.name, L10n.t("unsorted"))
    }

    func testMissingLocationBorrowedFromNearbyTime() {
        let items = [Fixtures.item("a", date: d("2026:11:02 10:00:00"), lat: 35, lon: 135.7),
                     Fixtures.item("b", date: d("2026:11:02 11:00:00")),
                     Fixtures.item("c", date: d("2026:11:02 20:00:00"))]
        let pts = Grouping.fillMissingLocations(items)
        XCTAssertNotNil(pts["b"])          // 1 小時內：借得到
        XCTAssertNil(pts["c"])             // 10 小時：借不到
    }

    func testByPlaceTwoCountriesNestsCities() async {
        let items = [Fixtures.item("k1", date: d("2026:11:02 10:00:00"), lat: 35.0, lon: 135.7),
                     Fixtures.item("t1", date: d("2026:11:04 10:00:00"), lat: 35.6, lon: 139.6),
                     Fixtures.item("p1", date: d("2026:11:06 10:00:00"), lat: 25.0, lon: 121.5),
                     Fixtures.item("n1", date: nil)]
        let g = await Grouping.byPlace(items, lookup: FakeLookup())
        XCTAssertEqual(g.map(\.name), ["日本", "台灣", L10n.t("unsorted")])
        XCTAssertEqual(g[0].children.map(\.name), ["京都市", "東京"])
        XCTAssertEqual(g[1].itemIDs, ["p1"])          // 只有一個城市：不再分子主題
        XCTAssertEqual(Grouping.dominantCountry(g), "JP")
    }

    func testByPlaceSingleCountryUsesCities() async {
        let items = [Fixtures.item("k1", date: d("2026:11:02 10:00:00"), lat: 35.0, lon: 135.7),
                     Fixtures.item("t1", date: d("2026:11:04 10:00:00"), lat: 35.6, lon: 139.6)]
        let g = await Grouping.byPlace(items, lookup: FakeLookup())
        XCTAssertEqual(g.map(\.name), ["京都市", "東京"])
    }

    func testCityNameRules() {
        XCTAssertEqual(AppleGeocoder.cityName(iso: "JP", admin: "東京", subAdmin: nil, locality: "杉並區"), "東京")
        XCTAssertEqual(AppleGeocoder.cityName(iso: "TW", admin: "臺北市", subAdmin: "臺北市", locality: "信義區"), "臺北市")
        XCTAssertEqual(AppleGeocoder.cityName(iso: "TW", admin: "Taichung City", subAdmin: "Taichung City", locality: "West District"), "Taichung City")
        XCTAssertEqual(AppleGeocoder.cityName(iso: "HK", admin: "九龍", subAdmin: "油尖旺區", locality: "旺角"), "香港")
        XCTAssertEqual(AppleGeocoder.cityName(iso: "JP", admin: "京都府", subAdmin: nil, locality: "京都市"), "京都市")
        XCTAssertEqual(AppleGeocoder.cityName(iso: "US", admin: "NY", subAdmin: "New York County", locality: "New York"), "New York")
    }

    func testSafeFolderNames() {
        XCTAssertEqual(Grouping.safeName("a/b:c"), "a／b：c")
        XCTAssertEqual(Grouping.safeName("_hidden"), "hidden")
        XCTAssertEqual(Grouping.safeName("  "), "untitled")
    }
}

final class MetadataTests: XCTestCase {
    func testExifDateWithOffset() {
        let (date, off) = MetadataReader.parseExifDate("2026:11:02 10:00:00", offset: "+09:00")!
        XCTAssertEqual(off, 32400)
        XCTAssertEqual(ISO8601DateFormatter().string(from: date), "2026-11-02T01:00:00Z")
    }

    func testISO6709() {
        let p = MetadataReader.parseISO6709("+35.0116+135.7681+050.000/")!
        XCTAssertEqual(p.lat, 35.0116, accuracy: 1e-6)
        XCTAssertEqual(p.lon, 135.7681, accuracy: 1e-6)
        XCTAssertEqual(MetadataReader.parseISO6709("-33.86+151.21/")!.lat, -33.86, accuracy: 1e-6)
    }

    func testReadsGPSFromFile() {
        let dir = Fixtures.tempDir("meta")
        let f = dir.appendingPathComponent("a.jpg")
        Fixtures.photo(f, date: "2026:11:02 10:00:00", offset: "+09:00", lat: 35.01, lon: -135.76)
        let item = MetadataReader.read(f)
        XCTAssertEqual(item.location!.lat, 35.01, accuracy: 1e-4)
        XCTAssertEqual(item.location!.lon, -135.76, accuracy: 1e-4)
        XCTAssertEqual(item.utcOffset, 32400)
    }

    func testUpdateVersionCompare() {
        XCTAssertTrue(Updates.isNewer("1.0.0", than: "0.9.0"))
        XCTAssertTrue(Updates.isNewer("0.10.0", than: "0.9.3"))
        XCTAssertFalse(Updates.isNewer("0.9.0", than: "0.9.0"))
    }

    func testExtractJSONFromChattyReply() {
        let j = PiClient.extractJSON("好的！\n```json\n{\"title\":\"京都\",\"groups\":[]}\n```")
        XCTAssertEqual(j?["title"] as? String, "京都")
    }
}
