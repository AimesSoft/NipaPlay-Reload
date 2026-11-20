"""The bundled harness tools' transport; local fixtures only, no network."""
import gzip
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import zlib

TOOLS = Path(__file__).resolve().parents[2] / "assets/next/harness/tools"
sys.path.insert(0, str(TOOLS))
import public_http
import rss


class Encodings(unittest.TestCase):
    body = "<i><d p=\"1,1,25,16777215,1,0,0,0\">弹幕</d></i>".encode()

    def test_compressed_bodies_are_unpacked(self):
        raw = zlib.compressobj(wbits=-zlib.MAX_WBITS)
        deflated_raw = raw.compress(self.body) + raw.flush()
        for encoding, sent in [
            (None, self.body),
            ("identity", self.body),
            ("gzip", gzip.compress(self.body)),
            ("deflate", zlib.compress(self.body)),
            # comment.bilibili.com: raw deflate, sent even when asked for identity.
            ("deflate", deflated_raw),
        ]:
            self.assertEqual(public_http.decoded(sent, encoding), self.body, encoding)

    def test_a_bomb_is_held_to_the_limit(self):
        bomb = gzip.compress(b"\0" * (public_http.MAX_BYTES + 1024))
        with self.assertRaises(ValueError):
            public_http.decoded(bomb, "gzip")

    def test_unknown_or_broken_encodings_fail_plainly(self):
        with self.assertRaises(RuntimeError):
            public_http.decoded(self.body, "br")
        with self.assertRaises(RuntimeError):
            public_http.decoded(b"not compressed", "gzip")


class FeedCredentials(unittest.TestCase):
    def test_a_search_keyword_is_not_a_credential(self):
        with patch.object(rss, "fetch", return_value=b"<rss><channel></channel></rss>"):
            result = rss.read("https://share.dmhy.org/topics/rss/rss.xml?keyword=frieren")
        self.assertEqual(result["entries"], [])

    def test_credentials_in_the_url_still_need_a_named_secret(self):
        for query in ["apikey=x", "api_key=x", "x-api-key=x", "key=x", "passkey=x", "token=x"]:
            with self.assertRaises(ValueError, msg=query):
                rss.read("https://feed.invalid/rss?" + query)


if __name__ == "__main__":
    unittest.main()
