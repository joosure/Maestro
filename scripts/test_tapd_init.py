import unittest
import sys
from pathlib import Path
import importlib.machinery
import importlib.util

# Paths
scripts_dir = Path(__file__).resolve().parent

# Ensure scripts_dir is in sys.path so tapd-workflow-init can import workflow_template_utils
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

# Load tapd-workflow-init dynamically using SourceFileLoader to avoid creating temp files
loader = importlib.machinery.SourceFileLoader("tapd_init", str(scripts_dir / "tapd-workflow-init"))
spec = importlib.util.spec_from_loader(loader.name, loader)
tapd_init = importlib.util.module_from_spec(spec)
loader.exec_module(tapd_init)

class TestTapdInitHeuristics(unittest.TestCase):
    def test_pick_state_by_heuristics_exact(self):
        states = [
            {"raw": "status_1", "display": "待开发"},
            {"raw": "status_2", "display": "开发中"},
            {"raw": "status_3", "display": "测试中"}
        ]
        self.assertEqual(
            tapd_init.pick_state_by_heuristics(states, ["开发中", "developing"]),
            ["status_2"]
        )
        self.assertEqual(
            tapd_init.pick_state_by_heuristics(states, ["待开发", "planning"]),
            ["status_1"]
        )

    def test_pick_state_by_heuristics_substring(self):
        states = [
            {"raw": "status_2", "display": "Coding_Work"},
            {"raw": "status_3", "display": "QA_Review"}
        ]
        self.assertEqual(
            tapd_init.pick_state_by_heuristics(states, ["coding"]),
            ["status_2"]
        )
        self.assertEqual(
            tapd_init.pick_state_by_heuristics(states, ["review"]),
            ["status_3"]
        )

    def test_pick_state_by_heuristics_exact_match_no_shortcut(self):
        states = [
            {"raw": "testing", "display": "测试"},
            {"raw": "status_3", "display": "待测试"}
        ]
        # testing exact matches 'testing'
        # status_3 display '待测试' fuzzy matches '测试'
        # Since review_kws = ["测试", ..., "testing"], it must return both without shortcutting
        cands = tapd_init.pick_state_by_heuristics(states, ["测试", "testing"])
        self.assertIn("testing", cands)
        self.assertIn("status_3", cands)
        self.assertEqual(len(cands), 2)

    def test_infer_route_states_all_matched(self):
        first_states = [
            {"raw": "status_1", "display": "新需求"},
            {"raw": "status_2", "display": "开始开发"},
            {"raw": "status_3", "display": "提测/代码评审"},
            {"raw": "status_4", "display": "合并分支"},
            {"raw": "status_5", "display": "重新修改"}
        ]
        terminal_states = [
            {"raw": "status_6", "display": "完成上线"},
            {"raw": "status_7", "display": "取消废弃"}
        ]
        all_states = first_states + terminal_states

        inferred = tapd_init.infer_route_states(first_states, terminal_states, all_states)

        self.assertEqual(inferred["planning"], ["status_1"])
        self.assertEqual(inferred["developing"], ["status_2"])
        self.assertEqual(inferred["review"], ["status_3"])
        self.assertEqual(inferred["merging"], ["status_4"])
        self.assertEqual(inferred["rework"], ["status_5"])
        self.assertEqual(inferred["resolved"], ["status_6"])
        self.assertEqual(inferred["rejected"], ["status_7"])

    def test_expected_route_states_heuristics_fallback(self):
        first_states = [
            {"raw": "status_1", "display": "待开发任务"},
            {"raw": "status_2", "display": "进行中"},
            {"raw": "status_3", "display": "测试中"},
            {"raw": "status_4", "display": "待发布"},
            {"raw": "status_5", "display": "返工修改"}
        ]
        terminal_states = [
            {"raw": "status_6", "display": "上线完成"},
            {"raw": "status_7", "display": "已丢弃"}
        ]
        all_states = first_states + terminal_states

        route_states = tapd_init.expected_route_states(first_states, terminal_states, all_states)

        self.assertEqual(route_states["planning"], "status_1")
        self.assertEqual(route_states["developing"], "status_2")
        self.assertEqual(route_states["review"], "status_3")
        self.assertEqual(route_states["merging"], "status_4")
        self.assertEqual(route_states["rework"], "status_5")
        self.assertEqual(route_states["resolved"], "status_6")
        self.assertEqual(route_states["rejected"], "status_7")

    def test_expected_route_states_multiple_candidates_fails(self):
        first_states = [
            {"raw": "status_1", "display": "待开发"},
            {"raw": "status_2", "display": "开发中"},
            {"raw": "status_3", "display": "待测试"},
            {"raw": "status_33", "display": "测试中"},
            {"raw": "status_4", "display": "合并中"},
            {"raw": "status_5", "display": "返工"}
        ]
        terminal_states = [
            {"raw": "status_6", "display": "已完成"},
            {"raw": "status_7", "display": "已拒绝"}
        ]
        all_states = first_states + terminal_states

        states_with_ambiguous_review = [
            {"raw": "status_1", "display": "待开发"},
            {"raw": "status_2", "display": "开发中"},
            {"raw": "status_3", "display": "待测试"},
            {"raw": "status_33", "display": "测试中"},
            {"raw": "status_4", "display": "合并中"},
            {"raw": "status_5", "display": "返工"},
            {"raw": "status_6", "display": "已完成"},
            {"raw": "status_7", "display": "已拒绝"}
        ]

        with self.assertRaises(SystemExit):
            tapd_init.expected_route_states(first_states, terminal_states, states_with_ambiguous_review)

    def test_expected_route_states_mapping_conflict_fails(self):
        first_states = [
            {"raw": "status_1", "display": "待开发"},
            {"raw": "status_4", "display": "合并中"},
            {"raw": "status_5", "display": "返工"}
        ]
        terminal_states = [
            {"raw": "status_6", "display": "已完成"},
            {"raw": "status_7", "display": "已拒绝"}
        ]
        # developing heuristics matches '待开发' (status_1) because of kw '开发'
        # but planning route already explicitly mapped to 'status_1'. This conflict must fail.
        states = [
            {"raw": "status_1", "display": "待开发"},
            {"raw": "status_3", "display": "评审中"},
            {"raw": "status_4", "display": "合并中"},
            {"raw": "status_5", "display": "返工"},
            {"raw": "status_6", "display": "已完成"},
            {"raw": "status_7", "display": "已拒绝"}
        ]
        with self.assertRaises(SystemExit):
            tapd_init.expected_route_states(first_states, terminal_states, states)

    def test_expected_backlog_state_heuristics_fallback(self):
        states = [
            {"raw": "status_backlog", "display": "MaestroBacklog"},
            {"raw": "status_1", "display": "待开发"}
        ]
        backlog = tapd_init.expected_backlog_state(states)
        self.assertEqual(backlog, "status_backlog")

if __name__ == "__main__":
    unittest.main()
