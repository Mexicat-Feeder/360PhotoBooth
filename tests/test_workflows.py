import unittest

from booth_backend import server


class WorkflowFilesTest(unittest.TestCase):
    ai_node_types = {
        "CheckpointLoaderSimple",
        "CLIPTextEncode",
        "VAEEncode",
        "KSampler",
        "VAEDecode",
    }

    def test_all_preset_workflows_load_from_json_files(self):
        for preset in server.PRESETS:
            for workflow in (preset.preview_workflow, preset.final_workflow):
                with self.subTest(workflow=workflow):
                    path = server._workflow_path(workflow)
                    self.assertTrue(path.exists(), f"{workflow} missing at {path}")
                    loaded = server._load_workflow(workflow)
                    self.assertIsInstance(loaded, dict)
                    self.assertTrue(loaded)

    def test_preset_workflows_use_ai_sampling_nodes(self):
        for preset in server.PRESETS:
            for workflow in (preset.preview_workflow, preset.final_workflow):
                with self.subTest(workflow=workflow):
                    loaded = server._load_workflow(workflow)
                    node_types = {
                        node.get("class_type")
                        for node in loaded.values()
                    }
                    self.assertTrue(self.ai_node_types.issubset(node_types))

    def test_workflow_patch_replaces_input_and_output_prefix(self):
        workflow = server._load_workflow("preset_chrome_negative_preview")

        patched = server._patch_workflow(
            workflow,
            input_name="uploaded_source.mp4",
            job_id="abc123",
        )

        load_nodes = [
            node for node in patched.values()
            if node.get("class_type") == "LoadVideo"
        ]
        save_nodes = [
            node for node in patched.values()
            if node.get("class_type") == "SaveVideo"
        ]

        self.assertEqual(load_nodes[0]["inputs"]["file"], "uploaded_source.mp4")
        self.assertEqual(
            save_nodes[0]["inputs"]["filename_prefix"],
            "booth_abc123",
        )


if __name__ == "__main__":
    unittest.main()
