"""Decoder boundary checks: empty entries must not become synthetic images."""
import struct
import unittest
import zlib

from export_mir3_appearance_frames import inspect_frame


def fixture(width=3, height=2, pixels=None):
    stride = (width * 2 + 3) // 4 * 4
    raw = bytes(range(stride * height)) if pixels is None else pixels
    compressed = zlib.compress(raw)
    index = bytearray(28)
    struct.pack_into("<II", index, 16, 1, 0)
    struct.pack_into("<I", index, 24, 24)
    frame = struct.pack("<HHhhI", width, height, -22, -78, len(compressed)) + bytes(4)
    return index, bytearray(24) + frame + compressed


class AppearanceFramesTest(unittest.TestCase):
    def test_zero_offset_is_missing_even_with_plausible_file_header(self):
        index, images = fixture()
        struct.pack_into("<I", index, 24, 0)
        images[:16] = struct.pack("<HHhhI", 1, 1, 0, 0, 12) + bytes(4)
        self.assertEqual(inspect_frame(index, images, 0),
                         {"image": 0, "file_offset": 0, "present": False})

    def test_odd_width_keeps_four_byte_row_padding(self):
        index, images = fixture()
        frame = inspect_frame(index, images, 0)
        self.assertEqual((frame["row_stride"], frame["decoded_bytes"]), (8, 16))
        self.assertEqual((frame["x_offset"], frame["y_offset"]), (-22, -78))

    def test_out_of_range_image_is_rejected(self):
        index, images = fixture()
        for number in [-1, 1]:
            with self.subTest(number=number), self.assertRaises(ValueError):
                inspect_frame(index, images, number)

    def test_invalid_offsets_do_not_read_another_record(self):
        index, images = fixture()
        for offset in [1, 23, len(images) - 8, 0xFFFFFFFF]:
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                struct.pack_into("<I", index, 24, offset)
                inspect_frame(index, images, 0)

    def test_short_and_oversized_decoded_rows_are_rejected(self):
        for size in [0, 12, 17, 100000]:
            with self.subTest(size=size), self.assertRaises(ValueError):
                index, images = fixture(pixels=bytes(size))
                inspect_frame(index, images, 0)

    def test_truncated_compressed_body_is_rejected(self):
        index, images = fixture()
        with self.assertRaises(ValueError):
            inspect_frame(index, images[:-1], 0)

    def test_second_compressed_stream_is_not_accepted_as_one_image(self):
        index, images = fixture()
        extra = zlib.compress(b"unexpected second frame")
        size = struct.unpack_from("<I", images, 32)[0]
        struct.pack_into("<I", images, 32, size + len(extra))
        with self.assertRaises(ValueError):
            inspect_frame(index, images + extra, 0)

    def test_other_storage_formats_are_not_silently_decoded(self):
        index, images = fixture()
        images[36] = 2
        with self.assertRaises(ValueError):
            inspect_frame(index, images, 0)


if __name__ == "__main__":
    unittest.main()
