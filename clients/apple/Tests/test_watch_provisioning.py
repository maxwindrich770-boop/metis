import datetime as dt
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("verify_watch_install",
    Path(__file__).resolve().parents[1] / "scripts/verify-watch-install.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
NOW = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)


class ProvisioningTests(unittest.TestCase):
    def profile(self, devices):
        return {"ProvisionedDevices": devices, "ExpirationDate": dt.datetime(2026, 1, 8),
                "Entitlements": {"application-identifier": "TEAM.test.watch",
                                 "com.apple.developer.team-identifier": "TEAM"}}

    def errors(self, profile):
        return validator.profile_errors(profile, "test.watch", "watch-device", "TEAM", NOW)

    def test_phone_only_profile_cannot_install_on_watch(self):
        self.assertIn("PROFILE_MISSING_DEVICE", self.errors(self.profile(["phone-device"])))

    def test_registered_watch_and_correct_application_are_accepted(self):
        self.assertEqual(self.errors(self.profile(["phone-device", "watch-device"])), [])

    def test_wrong_app_or_team_are_rejected(self):
        profile = self.profile(["watch-device"])
        profile["Entitlements"]["application-identifier"] = "TEAM.other.app"
        profile["Entitlements"]["com.apple.developer.team-identifier"] = "OTHER"
        self.assertCountEqual(self.errors(profile), ["PROFILE_WRONG_APP", "PROFILE_WRONG_TEAM"])

    def test_expired_profile_is_rejected(self):
        profile = self.profile(["watch-device"])
        profile["ExpirationDate"] = NOW.replace(tzinfo=None)
        self.assertEqual(self.errors(profile), ["PROFILE_EXPIRED"])

    def test_explicit_wildcard_profile_is_supported(self):
        profile = self.profile(["watch-device"])
        profile["Entitlements"]["application-identifier"] = "TEAM.test.*"
        self.assertEqual(self.errors(profile), [])


if __name__ == "__main__":
    unittest.main()
