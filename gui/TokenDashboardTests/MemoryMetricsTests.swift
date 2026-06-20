import XCTest
@testable import TokenDashboard

final class MemoryMetricsTests: XCTestCase {

    private func makeTypicalSnapshot() -> UsageSnapshot {
        let modelData: [String: Any] = [
            "model_name": "abab6.5s-chat",
            "current_interval_remaining_percent": 65.0,
            "current_weekly_remaining_percent": 80.0,
            "end_time": 1718700000000.0,
            "weekly_end_time": 1719304800000.0,
            "extra_field_1": "some value that adds bulk",
            "extra_field_2": [1, 2, 3, 4, 5],
            "extra_field_3": ["nested": ["key": "value"]],
        ]
        let windows = [
            QuotaWindow(
                kind: .rolling5h, label: "5h", used: 35, limit: 100,
                remaining: 65, unit: .percent, usedPct: 35,
                raw: modelData.mapValues { JSONValue.from($0) }
            ),
            QuotaWindow(
                kind: .rollingWeek, label: "week", used: 20, limit: 100,
                remaining: 80, unit: .percent, usedPct: 20,
                raw: modelData.mapValues { JSONValue.from($0) }
            ),
        ]
        let fullRaw: [String: Any] = [
            "model_remains": [modelData],
            "code": 0,
            "message": "success",
        ]
        return UsageSnapshot(
            provider: .minimax,
            fetchedAt: Date(),
            planName: "MiniMax Token Plan",
            planKind: .tokenPlan,
            windows: windows,
            authMode: "api_key",
            raw: fullRaw.mapValues { JSONValue.from($0) }
        )
    }

    private func makeLeanSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            provider: .minimax,
            fetchedAt: Date(),
            planName: "MiniMax Token Plan",
            planKind: .tokenPlan,
            windows: [
                QuotaWindow(kind: .rolling5h, label: "5h", used: 35, limit: 100, remaining: 65, unit: .percent, usedPct: 35, raw: [:]),
                QuotaWindow(kind: .rollingWeek, label: "week", used: 20, limit: 100, remaining: 80, unit: .percent, usedPct: 20, raw: [:]),
            ],
            authMode: "api_key",
            raw: [:]
        )
    }

    func testRawFieldEncodingOverhead() throws {
        let full = makeTypicalSnapshot()
        let lean = makeLeanSnapshot()
        let fullData = try JSONEncoder().encode(full)
        let leanData = try JSONEncoder().encode(lean)
        let fullSize = fullData.count
        let leanSize = leanData.count
        let rawOverhead = fullSize - leanSize
        let rawPct = Double(rawOverhead) / Double(fullSize) * 100
        print("📊 Encoding size — Full: \(fullSize) bytes, Lean: \(leanSize) bytes, raw overhead: \(rawOverhead) bytes (\(String(format: "%.1f", rawPct))%)")
        XCTAssertGreaterThan(rawPct, 40, "raw field should account for >40% of encoded data")
    }

    func testQuotaWindowRawDuplication() throws {
        let usageData: [String: Any] = [
            "rp5hLimit": 100, "rp5hUsage": 30,
            "rpwLimit": 500, "rpwUsage": 200,
            "packageLimit": 1000, "packageUsage": 600,
            "extra": "bulk data here",
        ]
        let windows = [
            QuotaWindow(kind: .rolling5h, label: "5h", used: 30, limit: 100, remaining: 70, unit: .requests, usedPct: 30, raw: usageData.mapValues { JSONValue.from($0) }),
            QuotaWindow(kind: .rolling5h, label: "5h", used: 30, limit: 100, remaining: 70, unit: .requests, usedPct: 30, raw: usageData.mapValues { JSONValue.from($0) }),
            QuotaWindow(kind: .rolling5h, label: "5h", used: 30, limit: 100, remaining: 70, unit: .requests, usedPct: 30, raw: usageData.mapValues { JSONValue.from($0) }),
        ]
        let w0Data = try JSONEncoder().encode(windows[0])
        let w1Data = try JSONEncoder().encode(windows[1])
        let w2Data = try JSONEncoder().encode(windows[2])
        XCTAssertEqual(w0Data.count, w1Data.count)
        XCTAssertEqual(w1Data.count, w2Data.count)
        let leanWindow = QuotaWindow(kind: .rolling5h, label: "5h", used: 30, limit: 100, remaining: 70, unit: .requests, usedPct: 30, raw: [:])
        let leanData = try JSONEncoder().encode(leanWindow)
        let rawPerWindow = w0Data.count - leanData.count
        let totalDuplication = rawPerWindow * 3
        print("📊 Raw duplication — Per window raw: \(rawPerWindow) bytes, Total duplicated: \(totalDuplication) bytes (3 copies of same data)")
        XCTAssertGreaterThan(rawPerWindow, 0, "raw field should add encoding overhead per window")
    }

    func testRealWorldAdapterComparison() throws {
        let minimaxAdapter = MiniMaxAdapter()
        let xunfeiAdapter = XunfeiAdapter()
        let deepseekAdapter = DeepSeekAdapter()
        let mimoAdapter = MiMoAdapter()

        let minimaxResponse: [String: Any] = [
            "model_remains": [
                [
                    "model_name": "abab6.5s-chat",
                    "current_interval_remaining_percent": 65.0,
                    "current_weekly_remaining_percent": 80.0,
                    "end_time": 1718700000000.0,
                    "weekly_end_time": 1719304800000.0,
                ]
            ],
            "code": 0,
            "message": "success",
        ]

        let xunfeiPlan: [String: Any] = [
            "name": "Coding Plan",
            "appId": "test@app.com",
            "expiresAt": "2026-12-31 23:59:59",
            "codingPlanUsageDTO": [
                "rp5hLimit": 100, "rp5hUsage": 30,
                "rpwLimit": 500, "rpwUsage": 200,
                "packageLimit": 1000, "packageUsage": 600,
            ] as [String: Any],
        ]

        let deepseekResponse: [String: Any] = [
            "balance_infos": [
                ["currency": "CNY", "total_balance": "10.50"]
            ] as [[String: Any]],
        ]

        let mimoTokenPlanData: [String: Any] = [
            "monthUsage": [
                "items": [["name": "month_total_token", "used": 5000.0, "limit": 50000.0]] as [[String: Any]]
            ],
            "usage": [
                "items": [["name": "plan_total_token", "used": 10000.0, "limit": 100000.0]] as [[String: Any]]
            ],
        ]

        var leanSnapshots: [UsageSnapshot] = []
        leanSnapshots.append(UsageSnapshot(
            provider: .minimax, fetchedAt: Date(), planName: "MiniMax Token Plan",
            planKind: .tokenPlan, windows: minimaxAdapter.parseAPIResponse(minimaxResponse).windows,
            authMode: "api_key", raw: [:]
        ))
        leanSnapshots.append(UsageSnapshot(
            provider: .xunfei, fetchedAt: Date(), planName: "Coding Plan",
            planKind: .codingPlan, windows: xunfeiAdapter.parseUsage(xunfeiPlan),
            accountEmail: "test@app.com", authMode: "cookie", raw: [:]
        ))
        leanSnapshots.append(UsageSnapshot(
            provider: .deepseek, fetchedAt: Date(), planName: "DeepSeek Pay-as-you-go",
            planKind: .payAsYouGo, balance: 10.50, balanceUnit: .cny,
            authMode: "api_key", raw: [:]
        ))
        leanSnapshots.append(UsageSnapshot(
            provider: .mimo, fetchedAt: Date(), planName: "MiMo",
            planKind: .tokenPlan, windows: mimoAdapter.parseTokenPlan(mimoTokenPlanData),
            authMode: "cookie", raw: [:]
        ))

        var fatSnapshots: [UsageSnapshot] = []
        let minimaxParsed = minimaxAdapter.parseAPIResponse(minimaxResponse)
        fatSnapshots.append(UsageSnapshot(
            provider: .minimax, fetchedAt: Date(), planName: "MiniMax Token Plan",
            planKind: .tokenPlan, windows: minimaxParsed.windows,
            authMode: "api_key", raw: minimaxResponse.mapValues { JSONValue.from($0) }
        ))
        fatSnapshots.append(UsageSnapshot(
            provider: .xunfei, fetchedAt: Date(), planName: "Coding Plan",
            planKind: .codingPlan, windows: xunfeiAdapter.parseUsage(xunfeiPlan),
            accountEmail: "test@app.com", authMode: "cookie",
            raw: xunfeiPlan.mapValues { JSONValue.from($0) }
        ))
        fatSnapshots.append(UsageSnapshot(
            provider: .deepseek, fetchedAt: Date(), planName: "DeepSeek Pay-as-you-go",
            planKind: .payAsYouGo, balance: 10.50, balanceUnit: .cny,
            authMode: "api_key", raw: deepseekResponse.mapValues { JSONValue.from($0) }
        ))
        fatSnapshots.append(UsageSnapshot(
            provider: .mimo, fetchedAt: Date(), planName: "MiMo",
            planKind: .tokenPlan, windows: mimoAdapter.parseTokenPlan(mimoTokenPlanData),
            authMode: "cookie", raw: mimoTokenPlanData.mapValues { JSONValue.from($0) }
        ))

        let leanData = try JSONEncoder().encode(leanSnapshots)
        let fatData = try JSONEncoder().encode(fatSnapshots)
        let saved = fatData.count - leanData.count
        let savedPct = Double(saved) / Double(fatData.count) * 100

        print("========== Real-World Memory Optimization Comparison ==========")
        print("  Before (with raw):    \(fatData.count) bytes")
        print("  After  (without raw): \(leanData.count) bytes")
        print("  Saved:                \(saved) bytes (\(String(format: "%.1f", savedPct))%)")
        print("  Per-provider avg saved: \(saved / 4) bytes")
        print("===============================================================")

        XCTAssertGreaterThan(savedPct, 20, "Optimization should save >20% in real-world usage")
    }

    func testRuntimeObjectHeapSize() throws {
        let minimaxResponse: [String: Any] = [
            "model_remains": [
                [
                    "model_name": "abab6.5s-chat",
                    "current_interval_remaining_percent": 65.0,
                    "current_weekly_remaining_percent": 80.0,
                    "end_time": 1718700000000.0,
                    "weekly_end_time": 1719304800000.0,
                    "extra_field_1": "some value that adds bulk",
                    "extra_field_2": [1, 2, 3, 4, 5],
                    "extra_field_3": ["nested": ["key": "value"]],
                ]
            ],
            "code": 0,
            "message": "success",
        ]
        let xunfeiPlan: [String: Any] = [
            "name": "Coding Plan",
            "appId": "test@app.com",
            "expiresAt": "2026-12-31 23:59:59",
            "codingPlanUsageDTO": [
                "rp5hLimit": 100, "rp5hUsage": 30,
                "rpwLimit": 500, "rpwUsage": 200,
                "packageLimit": 1000, "packageUsage": 600,
            ] as [String: Any],
        ]
        let deepseekResponse: [String: Any] = [
            "balance_infos": [
                ["currency": "CNY", "total_balance": "10.50"]
            ] as [[String: Any]],
        ]
        let mimoTokenPlanData: [String: Any] = [
            "monthUsage": [
                "items": [["name": "month_total_token", "used": 5000.0, "limit": 50000.0]] as [[String: Any]]
            ],
            "usage": [
                "items": [["name": "plan_total_token", "used": 10000.0, "limit": 100000.0]] as [[String: Any]]
            ],
        ]

        var fatSnapshots: [UsageSnapshot] = []
        fatSnapshots.append(UsageSnapshot(
            provider: .minimax, fetchedAt: Date(), planName: "MiniMax Token Plan",
            planKind: .tokenPlan,
            windows: [
                QuotaWindow(kind: .rolling5h, label: "5h", used: 35, limit: 100, remaining: 65, unit: .percent, usedPct: 35,
                            raw: minimaxResponse.mapValues { JSONValue.from($0) }),
                QuotaWindow(kind: .rollingWeek, label: "week", used: 20, limit: 100, remaining: 80, unit: .percent, usedPct: 20,
                            raw: minimaxResponse.mapValues { JSONValue.from($0) }),
            ],
            authMode: "api_key",
            raw: minimaxResponse.mapValues { JSONValue.from($0) }
        ))
        fatSnapshots.append(UsageSnapshot(
            provider: .xunfei, fetchedAt: Date(), planName: "Coding Plan",
            planKind: .codingPlan,
            windows: [
                QuotaWindow(kind: .rolling5h, label: "5h", used: 30, limit: 100, remaining: 70, unit: .requests, usedPct: 30,
                            raw: xunfeiPlan.mapValues { JSONValue.from($0) }),
                QuotaWindow(kind: .rollingWeek, label: "week", used: 200, limit: 500, remaining: 300, unit: .requests, usedPct: 40,
                            raw: xunfeiPlan.mapValues { JSONValue.from($0) }),
                QuotaWindow(kind: .fixedPeriod, label: "pkg", used: 600, limit: 1000, remaining: 400, unit: .requests, usedPct: 60,
                            raw: xunfeiPlan.mapValues { JSONValue.from($0) }),
            ],
            accountEmail: "test@app.com", authMode: "cookie",
            raw: xunfeiPlan.mapValues { JSONValue.from($0) }
        ))
        fatSnapshots.append(UsageSnapshot(
            provider: .deepseek, fetchedAt: Date(), planName: "DeepSeek Pay-as-you-go",
            planKind: .payAsYouGo, balance: 10.50, balanceUnit: .cny,
            authMode: "api_key", raw: deepseekResponse.mapValues { JSONValue.from($0) }
        ))
        fatSnapshots.append(UsageSnapshot(
            provider: .mimo, fetchedAt: Date(), planName: "MiMo",
            planKind: .tokenPlan,
            windows: [
                QuotaWindow(kind: .calendarMonth, label: "Monthly", used: 5000, limit: 50000, remaining: 45000, unit: .credits, usedPct: 10,
                            raw: mimoTokenPlanData.mapValues { JSONValue.from($0) }),
                QuotaWindow(kind: .rollingMonth, label: "Plan Total", used: 10000, limit: 100000, remaining: 90000, unit: .credits, usedPct: 10,
                            raw: mimoTokenPlanData.mapValues { JSONValue.from($0) }),
            ],
            authMode: "cookie", raw: mimoTokenPlanData.mapValues { JSONValue.from($0) }
        ))

        var leanSnapshots: [UsageSnapshot] = []
        leanSnapshots.append(UsageSnapshot(
            provider: .minimax, fetchedAt: Date(), planName: "MiniMax Token Plan",
            planKind: .tokenPlan,
            windows: [
                QuotaWindow(kind: .rolling5h, label: "5h", used: 35, limit: 100, remaining: 65, unit: .percent, usedPct: 35, raw: [:]),
                QuotaWindow(kind: .rollingWeek, label: "week", used: 20, limit: 100, remaining: 80, unit: .percent, usedPct: 20, raw: [:]),
            ],
            authMode: "api_key", raw: [:]
        ))
        leanSnapshots.append(UsageSnapshot(
            provider: .xunfei, fetchedAt: Date(), planName: "Coding Plan",
            planKind: .codingPlan,
            windows: [
                QuotaWindow(kind: .rolling5h, label: "5h", used: 30, limit: 100, remaining: 70, unit: .requests, usedPct: 30, raw: [:]),
                QuotaWindow(kind: .rollingWeek, label: "week", used: 200, limit: 500, remaining: 300, unit: .requests, usedPct: 40, raw: [:]),
                QuotaWindow(kind: .fixedPeriod, label: "pkg", used: 600, limit: 1000, remaining: 400, unit: .requests, usedPct: 60, raw: [:]),
            ],
            accountEmail: "test@app.com", authMode: "cookie", raw: [:]
        ))
        leanSnapshots.append(UsageSnapshot(
            provider: .deepseek, fetchedAt: Date(), planName: "DeepSeek Pay-as-you-go",
            planKind: .payAsYouGo, balance: 10.50, balanceUnit: .cny,
            authMode: "api_key", raw: [:]
        ))
        leanSnapshots.append(UsageSnapshot(
            provider: .mimo, fetchedAt: Date(), planName: "MiMo",
            planKind: .tokenPlan,
            windows: [
                QuotaWindow(kind: .calendarMonth, label: "Monthly", used: 5000, limit: 50000, remaining: 45000, unit: .credits, usedPct: 10, raw: [:]),
                QuotaWindow(kind: .rollingMonth, label: "Plan Total", used: 10000, limit: 100000, remaining: 90000, unit: .credits, usedPct: 10, raw: [:]),
            ],
            authMode: "cookie", raw: [:]
        ))

        let fatEncoded = try JSONEncoder().encode(fatSnapshots)
        let leanEncoded = try JSONEncoder().encode(leanSnapshots)

        let fatSize = fatEncoded.count
        let leanSize = leanEncoded.count
        let saved = fatSize - leanSize
        let savedPct = Double(saved) / Double(fatSize) * 100

        print("========== Runtime Object Comparison (4 providers, realistic data) ==========")
        print("  Before (with raw):    \(fatSize) bytes encoded")
        print("  After  (without raw): \(leanSize) bytes encoded")
        print("  Saved:                \(saved) bytes (\(String(format: "%.1f", savedPct))%)")
        print("  Per-provider avg:     \(saved / 4) bytes saved")
        print("============================================================================")

        XCTAssertGreaterThan(savedPct, 20, "Optimization should save >20% with realistic data")
    }

    func testLeanSnapshotRoundTrip() throws {
        let lean = makeLeanSnapshot()
        let data = try JSONEncoder().encode(lean)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.provider, .minimax)
        XCTAssertEqual(decoded.planName, "MiniMax Token Plan")
        XCTAssertEqual(decoded.windows.count, 2)
        XCTAssertEqual(decoded.windows[0].usedPct, 35)
        XCTAssertEqual(decoded.windows[1].usedPct, 20)
        XCTAssertEqual(decoded.raw, [:])
        XCTAssertEqual(decoded.windows[0].raw, [:])
    }
}
