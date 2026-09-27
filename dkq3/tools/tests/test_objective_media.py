# SPDX-License-Identifier: GPL-2.0-or-later
import unittest
import appearances


class ObjectiveMediaTests(unittest.TestCase):
    def test_image_override_preserves_hidden_geometry_and_character_heads(self):
        metadata = {'surfaces': [
            {'name': 'body_1', 'shader': 'skins/hiro_bod_1', 'target_surfaces': [0]},
            {'name': 'head_1', 'shader': 'skins/hiro_head', 'target_surfaces': [1]},
            {'name': 'ctf_flag', 'shader': 'models/dkq3/nodraw', 'target_surfaces': [2]},
            {'name': 'unused', 'shader': 'skins/ignored', 'target_surfaces': []},
        ]}
        self.assertEqual(appearances.binding_lines(metadata, 'skins/ctf_flaglred', body_only=False), [
            'body,skins/ctf_flaglred', 'head,skins/ctf_flaglred', 'ctf_flag,models/dkq3/nodraw'])
        self.assertEqual(appearances.binding_lines(metadata, 'skins/hiro_bod_8', body_only=True), [
            'body,skins/hiro_bod_8', 'head,skins/hiro_head', 'ctf_flag,models/dkq3/nodraw'])
