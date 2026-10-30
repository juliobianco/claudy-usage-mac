import XCTest
@testable import ClaudyCore

final class WeatherTests: XCTestCase {
    func testMetNoSymbolsMapToWMO() {
        let cases: [(String, Int)] = [
            ("clearsky_day", 0), ("fair_night", 1), ("partlycloudy_polartwilight", 2), ("cloudy", 3), ("fog", 45),
            ("lightrain", 61), ("rain", 63), ("heavyrain", 65), ("lightrainshowers_day", 80), ("heavyrainshowers_night", 82),
            ("lightsnow", 71), ("heavysnow", 75), ("snowshowers_day", 85), ("heavysleet", 67), ("sleet", 66),
            ("lightrainandthunder", 95), ("heavyrainshowersandthunder_day", 99), ("somethingnew", 3),
        ]
        for (symbol, code) in cases { XCTAssertEqual(Wx.metNoCode(symbol), code, symbol) }
    }

    func testMetNoResponseParses() throws {
        let json = """
        {"properties":{"timeseries":[{"data":{"instant":{"details":{"air_temperature":12.5,"wind_speed":5.0}},
        "next_1_hours":{"summary":{"symbol_code":"rainshowers_day"}}}}]}}
        """
        let w = try XCTUnwrap(Wx.metNoWeather(Data(json.utf8)))
        XCTAssertEqual(w.code, 81)
        XCTAssertEqual(w.temp, 12.5)
        XCTAssertEqual(w.wind, 18, accuracy: 0.001)
        XCTAssertNil(Wx.metNoWeather(Data("{}".utf8)))
    }
}
