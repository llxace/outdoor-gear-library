import Foundation

func weatherConditions(_ code: Int) -> (String, String) {
    switch code {
    case 0: return ("晴", "sun.max.fill")
    case 1...3: return ("多云", "cloud.sun.fill")
    case 45, 48: return ("雾", "cloud.fog.fill")
    case 51...67, 80...82: return ("雨", "cloud.rain.fill")
    case 71...77, 85, 86: return ("雪", "cloud.snow.fill")
    case 95...99: return ("雷暴", "cloud.bolt.rain.fill")
    default: return ("天气代码 \(code)", "cloud.fill")
    }
}
