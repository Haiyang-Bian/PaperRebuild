# Arithmetic audit of selected transcribed thesis tables, not model reproduction.
# Source: docs/摘要.pdf, SHA-256 recorded in docs/reading/sources.json.
# Printed/PDF pages: Table 3-6 and 3-7: 43/60; Table 4-8: 65/82;
# Table 7-5: 114/131; Table 7-19: 125/142. Units remain chapter-specific.

function report_table_arithmetic()
    relative_change(after, before) = 100 * (after - before) / before
    rows = [
        ("T3-6 total cost reduction (%)", -relative_change(23608.41, 26758.19)),
        ("T3-6 renewable utilization increase (percentage points)", 100.0 - 53.74),
        ("T3-7 small-case relative objective difference (%)", relative_change(13891.9, 13867.2)),
        ("T4-8 distributed welfare shortfall (%)", -relative_change(38934.32, 39220.96)),
        ("T7-5 total cost reduction (%)", -relative_change(382346.88, 390828.85)),
        ("T7-5 renewable utilization increase (percentage points)", 99.74 - 96.32),
        ("T7-19 4C cost increase vs 4A (%)", relative_change(409662.0, 405373.0)),
        ("T7-19 4B cost increase vs 4A (%)", relative_change(418616.0, 405373.0)),
        ("T7-19 4C unserved energy reduction vs 4A (%)", -relative_change(1.4603, 8.5454)),
    ]
    for (label, value) in rows
        println(label, ": ", round(value; digits = 6))
    end
    println("These are arithmetic comparisons, not feasibility or optimality certificates.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    report_table_arithmetic()
end
