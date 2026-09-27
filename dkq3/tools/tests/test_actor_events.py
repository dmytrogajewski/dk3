"""Sound alternatives and absent frame events survive local asset conversion."""
import unittest
import actor_events


class ActorEventsTest(unittest.TestCase):
    def convert(self, text):
        row = actor_events.records(text.encode(), 'synthetic.csv')[0]
        return actor_events.normalize(row, 'fixture', row['framename'], 'synthetic.csv')

    def test_sequential_second_cue_and_missing_default(self):
        result = self.convert('name,sound1,frame1,sound2,frame2,sound2%\n'
                              'runa,left.wav,2,right.wav,8,\n')
        self.assertEqual(result['sound2_alternative'], 0)
        self.assertEqual(result['sound2_chance'], 0)
        self.assertEqual(result['frame2_enabled'], 1)
        self.assertEqual(result['frame2'], 8)
        self.assertEqual(result['strike1'], 1)

    def test_explicit_zero_alternative_suppresses_sequential_second_frame(self):
        result = self.convert('name,sound1,frame1,sound2,frame2,sound2%\n'
                              'amba,first.wav,2,other.wav,8,0\n')
        self.assertEqual(result['sound2_alternative'], 1)
        self.assertEqual(result['sound2_chance'], 0)
        self.assertEqual(result['frame2_enabled'], 0)

    def test_fractional_probability_and_disabled_frames(self):
        result = self.convert('name,sound1,frame1,sound2,frame2,sound2%,anim%\n'
                              'amba,first.wav,-1,other.wav,-1,25.5,40.5\n')
        self.assertEqual(result['sound2_chance'], 25.5)
        self.assertEqual(result['weight'], 40.5)
        self.assertEqual(result['frame1_enabled'], 0)
        self.assertEqual(result['frame2_enabled'], 0)

    def test_absent_second_frame_is_not_a_second_sound_at_frame_one(self):
        result = self.convert('name,sound1,sound2\namba,first.wav,other.wav\n')
        self.assertEqual(result['frame1_enabled'], 1)
        self.assertEqual(result['frame2_enabled'], 0)


if __name__ == '__main__':
    unittest.main()
