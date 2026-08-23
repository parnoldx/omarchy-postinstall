#!/usr/bin/env python3
import unittest
from datetime import datetime
from importlib.machinery import SourceFileLoader
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
tbcal = SourceFileLoader("tbcal", str(ROOT / "sync-thunderbird-calendar")).load_module()

TZ = ZoneInfo("Europe/Berlin")


class FirstMeetingUrl(unittest.TestCase):
    def test_prefers_google_conference_over_description_noise(self):
        url = tbcal.first_meeting_url(
            "https://meet.google.com/abc-defg-hij",
            "See https://example.com/agenda and https://github.com/meet.the-team",
        )
        self.assertEqual(url, "https://meet.google.com/abc-defg-hij")

    def test_finds_zoom_teams_and_jitsi_in_free_text(self):
        self.assertIn("zoom.us", tbcal.first_meeting_url("join https://us02web.zoom.us/j/123?pwd=ab"))
        self.assertIn("teams.microsoft.com", tbcal.first_meeting_url(
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc"
        ))
        self.assertIn("jit.si", tbcal.first_meeting_url("room: https://meet.jit.si/Standup"))

    def test_ignores_meeting_words_that_are_not_the_host(self):
        self.assertEqual(tbcal.first_meeting_url("read https://github.com/meet.the-team/notes"), "")
        self.assertEqual(tbcal.first_meeting_url("https://example.com/zoom.us/not-a-meeting"), "")

    def test_skips_zoom_ics_download_in_favor_of_the_join_link(self):
        url = tbcal.first_meeting_url(
            "https://us02web.zoom.us/meeting/abc/ics?icsToken=tok",
            "Join Zoom Meeting https://us02web.zoom.us/j/88971526434?pwd=secret",
        )
        self.assertEqual(url, "https://us02web.zoom.us/j/88971526434?pwd=secret")

    def test_zoom_join_from_ics_filename(self):
        self.assertEqual(
            tbcal.zoom_join_from_disposition(
                "https://us02web.zoom.us/meeting/abc/ics?icsToken=tok",
                'attachment; filename=meeting-88971526434.ics',
            ),
            "https://us02web.zoom.us/j/88971526434",
        )


class VEventMeetingUrl(unittest.TestCase):
    def test_reads_google_conference_and_description_links(self):
        calendar = {"id": "work", "name": "Work", "color": "#7aa2f7"}
        window_start = datetime(2026, 8, 23, 0, 0, tzinfo=TZ)
        window_end = datetime(2026, 8, 23, 23, 59, tzinfo=TZ)
        block = """BEGIN:VEVENT
UID:standup-1
DTSTART:20260823T080000Z
DTEND:20260823T083000Z
SUMMARY:Standup
LOCATION:https://us02web.zoom.us/j/999
X-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij
DESCRIPTION:Notes at https://example.com/doc
END:VEVENT"""
        events = tbcal.events_from_vevent(block, calendar, TZ, window_start, window_end)
        self.assertTrue(events)
        self.assertEqual(events[0]["meetingUrl"], "https://meet.google.com/abc-defg-hij")
        self.assertEqual(events[0]["title"], "Standup")

    def test_zoom_ics_url_loses_to_join_link_in_description(self):
        calendar = {"id": "work", "name": "Work", "color": "#7aa2f7"}
        window_start = datetime(2026, 8, 23, 0, 0, tzinfo=TZ)
        window_end = datetime(2026, 8, 23, 23, 59, tzinfo=TZ)
        block = """BEGIN:VEVENT
UID:zoom-1
DTSTART:20260823T080000Z
DTEND:20260823T083000Z
SUMMARY:Zoom
URL:https://us02web.zoom.us/meeting/abc/ics?icsToken=tok
DESCRIPTION:Join Zoom Meeting\\nhttps://us02web.zoom.us/j/88971526434?pwd=secret
END:VEVENT"""
        events = tbcal.events_from_vevent(block, calendar, TZ, window_start, window_end)
        self.assertEqual(events[0]["meetingUrl"], "https://us02web.zoom.us/j/88971526434?pwd=secret")


if __name__ == "__main__":
    unittest.main()
