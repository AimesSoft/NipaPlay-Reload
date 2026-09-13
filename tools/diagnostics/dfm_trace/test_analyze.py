import unittest
from analyze import analyze


class TraceTests(unittest.TestCase):
    def test_distinguishes_wait_from_gpu_latency_with_separate_clocks(self):
        records = [
            {"event": name, "engine": 1, "frame": 7, "t_us": time}
            for name, time in [("enqueue", 100), ("process_begin", 25100),
                               ("process_end", 25600), ("draw_begin", 25600),
                               ("draw_submitted", 26000), ("gpu_complete", 27000)]
        ]
        records += [{"event": "dart_batch", "data": {"dropped": 0, "events": [
            {"event": "send_begin", "engine": 1, "frame": 7, "t_us": 9000000},
            {"event": "send_return", "engine": 1, "frame": 7, "t_us": 9026000},
        ]}}]
        stages = analyze(records)["stages"]
        self.assertEqual(stages["native_queue"]["max_ms"], 25)
        self.assertEqual(stages["gpu_completion_latency"]["max_ms"], 1)
        self.assertEqual(stages["dart_channel_roundtrip"]["max_ms"], 26)

    def test_reports_coalescing_and_sample_repetition_without_claiming_present(self):
        records = [
            {"event": "process_end", "engine": 1, "frame": frame, "t_us": frame}
            for frame in [1, 2]
        ] + [
            {"event": name, "engine": 1, "frame": 2, "t_us": time}
            for name, time in [("draw_submitted", 3), ("texture_sample", 4), ("texture_sample", 5)]
        ]
        report = analyze(records)
        self.assertEqual(report["prepared_without_draw"]["first_20"], [(1, 1)])
        self.assertEqual(report["repeated_latest_completion_at_texture_callback"], 1)

    def test_dropped_samples_are_explicit(self):
        report = analyze([{"event": "native_dropped", "count": 5},
                          {"event": "dart_batch", "data": {"dropped": 3, "events": []}}])
        self.assertEqual(report["loss"]["native_records"], 5)
        self.assertEqual(report["loss"]["dart_events"], 3)


if __name__ == "__main__":
    unittest.main()
