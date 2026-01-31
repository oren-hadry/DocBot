import json
from dataclasses import dataclass, asdict

from data.storage import user_locations_file


@dataclass
class UserLocations:
    locations: list[str]


class LocationsManager:
    def _recover_locations_from_text(self, text: str) -> list[str] | None:
        if not text:
            return None
        # Try to parse JSON object first.
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1 and end > start:
            try:
                data = json.loads(text[start : end + 1])
                values = data.get("locations", [])
                if isinstance(values, list):
                    return [v for v in values if isinstance(v, str)]
            except Exception:
                pass
        # Try to parse a raw list if present.
        start = text.find("[")
        end = text.rfind("]")
        if start != -1 and end != -1 and end > start:
            try:
                values = json.loads(text[start : end + 1])
                if isinstance(values, list):
                    return [v for v in values if isinstance(v, str)]
            except Exception:
                pass
        return None

    def _sanitize_location(self, value: str) -> str:
        if not value:
            return ""
        cleaned = value.replace("\uFFFD", "")
        # Remove control chars and bidi marks that can render as gibberish.
        cleaned = cleaned.translate(
            {ord(ch): None for ch in "\u200E\u200F\u202A\u202B\u202C\u202D\u202E\u2066\u2067\u2068\u2069"}
        )
        cleaned = "".join(ch for ch in cleaned if ch.isprintable())
        return cleaned.strip()

    def _sanitize_list(self, values: list[str]) -> list[str]:
        cleaned = [self._sanitize_location(v) for v in values]
        return [v for v in cleaned if v]

    def get_locations(self, user_id: int) -> list[str]:
        path = user_locations_file(user_id)
        if path.exists():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    content = f.read()
                data = json.loads(content)
                locations = data.get("locations", [])
            except Exception:
                recovered = self._recover_locations_from_text(content if "content" in locals() else "")
                if recovered is not None:
                    locations = recovered
                else:
                    try:
                        path.unlink(missing_ok=True)
                    except Exception:
                        pass
                    return []
            sanitized = self._sanitize_list(locations)
            if sanitized != locations:
                with open(path, "w", encoding="utf-8") as out:
                    json.dump({"locations": sanitized}, out, ensure_ascii=False, indent=2)
            return sanitized
        return []

    def add_location(self, user_id: int, location: str, max_items: int = 5) -> None:
        location = self._sanitize_location(location)
        if not location:
            return
        locations = self.get_locations(user_id)
        deduped = [l for l in locations if l.lower() != location.lower()]
        new_list = [location] + deduped
        if len(new_list) > max_items:
            new_list = new_list[:max_items]
        path = user_locations_file(user_id)
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"locations": new_list}, f, ensure_ascii=False, indent=2)


locations_manager = LocationsManager()
