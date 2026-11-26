"""Hermes Kurulum Asistani - non-interactive model endpoint helper.

Runs INSIDE the installed Hermes runtime (the payload's own Python) and reuses Hermes' own code:

  probe  -> hermes_cli.models.probe_api_models  (the same /models probe `hermes model` runs)
  apply  -> hermes_cli.model_setup_flows_custom._model_flow_custom, i.e. EXACTLY the
            `hermes model` -> "Custom endpoint" wizard, with its prompts answered from the
            request instead of the keyboard. Hermes itself decides where things go:
            the API key goes to HERMES_HOME/.env (under the endpoint's own variable name) and
            config.yaml only references it as ${VAR}; the endpoint is also saved under
            custom_providers with the display name.
  show   -> current model / provider / base_url (never the key)

The request (including the API key) is read as ONE JSON object from stdin, never from the
command line. Everything the wizard prints is captured and returned with every secret
(and every 8-character key prefix Hermes likes to echo) replaced by ****.

Output: exactly one line `@@RESULT@@ {json}` on stdout. Exit code 0 = ok, 2 = handled error.
"""

from __future__ import annotations

import argparse
import builtins
import contextlib
import io
import json
import os
import site
import sys
import traceback

RESULT_MARK = "@@RESULT@@ "


class Redactor:
    def __init__(self) -> None:
        self.secrets: list[str] = []

    def add(self, value) -> None:
        value = str(value or "").strip()
        if len(value) < 4:
            return
        for s in (value, value[:8]):
            if len(s) >= 4 and s not in self.secrets:
                self.secrets.append(s)
        self.secrets.sort(key=len, reverse=True)

    def __call__(self, text) -> str:
        text = str(text or "")
        for s in self.secrets:
            text = text.replace(s, "****")
        return text


REDACT = Redactor()


def emit(ok: bool, **data) -> int:
    data["ok"] = ok
    # Redact every string in the result, recursively.
    def clean(v):
        if isinstance(v, str):
            return REDACT(v)
        if isinstance(v, list):
            return [clean(x) for x in v]
        if isinstance(v, dict):
            return {k: clean(x) for k, x in v.items()}
        return v
    sys.stdout.write(RESULT_MARK + json.dumps(clean(data), ensure_ascii=False) + "\n")
    sys.stdout.flush()
    return 0 if ok else 2


def setup_paths(args) -> None:
    """Make the Hermes payload importable (same layout install-stamp.json -> runtime describes)."""
    if args.site_packages:
        site.addsitedir(args.site_packages)       # also runs .pth files (hermes-agent.pth, pywin32.pth)
    if args.repo and args.repo not in sys.path:
        sys.path.insert(0, args.repo)


def install_trust() -> str:
    try:
        from agent.ssl_verify import install_truststore
        return "platform+env" if install_truststore() else "openssl-default"
    except Exception as exc:  # older payloads
        return f"unavailable ({type(exc).__name__})"


def read_request() -> dict:
    raw = sys.stdin.read()
    req = json.loads(raw) if raw.strip() else {}
    if not isinstance(req, dict):
        raise ValueError("request must be a JSON object")
    REDACT.add(req.get("api_key"))
    return req


def diagnose(url: str, api_key: str, timeout: float) -> dict:
    """Why did /models not answer? One plain GET with Hermes' own TLS context."""
    import ssl
    import urllib.error
    import urllib.request
    req = urllib.request.Request(url, headers={"User-Agent": "hermes-kurulum-asistani"})
    if api_key:
        req.add_header("Authorization", f"Bearer {api_key}")
    ctx = None
    try:
        from agent.ssl_verify import platform_ssl_context
        ctx = platform_ssl_context()
    except Exception:
        ctx = None
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            return {"code": "http_ok_unparsed", "status": resp.status, "detail": "The server answered but not with a model list."}
    except urllib.error.HTTPError as exc:
        code = "unauthorized" if exc.code in (401, 403) else ("not_found" if exc.code == 404 else "http_error")
        return {"code": code, "status": exc.code, "detail": str(exc.reason)}
    except urllib.error.URLError as exc:
        reason = exc.reason
        if isinstance(reason, ssl.SSLCertVerificationError) or "CERTIFICATE_VERIFY_FAILED" in str(reason):
            return {"code": "tls_untrusted", "detail": str(reason)}
        if isinstance(reason, ssl.SSLError):
            return {"code": "tls_error", "detail": str(reason)}
        if isinstance(reason, TimeoutError) or "timed out" in str(reason).lower():
            return {"code": "timeout", "detail": str(reason)}
        return {"code": "connect_failed", "detail": str(reason)}
    except TimeoutError as exc:
        return {"code": "timeout", "detail": str(exc)}
    except Exception as exc:  # noqa: BLE001
        return {"code": "error", "detail": f"{type(exc).__name__}: {exc}"}


def cmd_probe(req: dict) -> int:
    base_url = str(req.get("base_url") or "").strip()
    api_key = str(req.get("api_key") or "").strip()
    timeout = float(req.get("timeout") or 10)
    if not base_url.lower().startswith(("http://", "https://")):
        return emit(False, error="invalid_url", message="URL must start with http:// or https://")
    trust = install_trust()
    from hermes_cli.models import probe_api_models
    probe = probe_api_models(api_key, base_url, timeout=timeout)
    models = probe.get("models")
    out = {
        "trust": trust,
        "models": [str(m) for m in (models or [])],
        "answered": models is not None,
        "probed_url": probe.get("probed_url"),
        "resolved_base_url": probe.get("resolved_base_url"),
        "used_fallback": bool(probe.get("used_fallback")),
        "suggested_base_url": probe.get("suggested_base_url"),
    }
    if models is None:
        url = str(probe.get("probed_url") or (base_url.rstrip("/") + "/models"))
        out["diagnosis"] = diagnose(url, api_key, timeout)
        return emit(False, error="no_models", **out)
    return emit(True, **out)


class Answers:
    """Answers the `hermes model` -> Custom endpoint prompts. An unknown prompt aborts the
    flow (EOFError -> Hermes prints 'Cancelled.') instead of guessing."""

    def __init__(self, req: dict) -> None:
        self.base_url = str(req.get("base_url") or "").strip()
        self.api_key = str(req.get("api_key") or "").strip()
        self.model = str(req.get("model") or "").strip()
        self.display_name = str(req.get("display_name") or "").strip()
        cl = req.get("context_length")
        self.context_length = "" if cl in (None, "", 0) else str(cl).strip()
        self.add_v1 = bool(req.get("add_v1", False))
        self.api_mode = str(req.get("api_mode") or "").strip() or None   # None = Auto-detect
        self.asked: list[str] = []

    def _log(self, prompt: str, answer: str, secret: bool = False) -> str:
        self.asked.append(f"{prompt.strip()} -> {'(gizli)' if secret else (answer if answer else '(bos)')}")
        return answer

    def line_input(self, prompt: str = "") -> str:
        p = str(prompt)
        if p.startswith("API base URL"):
            return self._log(p, self.base_url)
        if p.startswith("Model name"):
            return self._log(p, self.model)
        if p.startswith("Context length"):
            return self._log(p, self.context_length)
        if p.startswith("Display name"):
            return self._log(p, self.display_name)
        self.asked.append(f"{p.strip()} -> (unknown prompt, aborted)")
        raise EOFError(f"unexpected prompt: {p.strip()}")

    def secret(self, prompt: str = "", **_kw) -> str:
        p = str(prompt)
        if p.startswith("API key"):
            return self._log(p, self.api_key, secret=True)
        self.asked.append(f"{p.strip()} -> (unknown secret prompt, aborted)")
        raise EOFError(f"unexpected secret prompt: {p.strip()}")

    def input(self, prompt: str = "") -> str:
        p = str(prompt).strip()
        if p.startswith("Use this model?"):
            # Single detected model: accept it only if it is the one chosen, else type the name.
            return self._log(p, "y" if self._detected_single == self.model else "n")
        if p.startswith("Select model"):
            return self._log(p, self.model)      # typing the name is accepted by the picker
        if p.startswith("Choice [1-4"):
            return self._log(p, "1" if not self.api_mode else self.api_mode)
        self.asked.append(f"{p} -> (unknown prompt, aborted)")
        raise EOFError(f"unexpected prompt: {p}")

    _detected_single = ""

    def ask(self, prompt: str, **_kw) -> str:
        p = str(prompt).strip()
        if p.startswith("Add /v1?"):
            return self._log(p, "y" if self.add_v1 else "n")
        self.asked.append(f"{p} -> (unknown prompt, aborted)")
        raise EOFError(f"unexpected prompt: {p}")


def cmd_apply(req: dict) -> int:
    ans = Answers(req)
    if not ans.base_url.lower().startswith(("http://", "https://")):
        return emit(False, error="invalid_url", message="URL must start with http:// or https://")
    if not ans.model:
        return emit(False, error="no_model", message="A model must be chosen.")
    trust = install_trust()

    from hermes_cli.config import get_env_value, load_config
    REDACT.add(get_env_value("OPENAI_API_KEY") or "")

    import hermes_cli.main_provider_setup as mps
    import hermes_cli.model_setup_flows_custom as flows
    import hermes_cli.secret_prompt as secret_prompt

    # Hermes' own probe decides the "single detected model" question, the same way the wizard does.
    real_pick = flows._pick_detected_model

    def pick(detected):
        ans._detected_single = str(detected[0]) if len(detected) == 1 else ""
        return real_pick(detected)

    def api_mode_prompt(base_url, current_api_mode=""):
        ans.asked.append(f"API compatibility mode -> {ans.api_mode or 'Auto-detect'}")
        return ans.api_mode

    patches = [
        (flows, "line_input", ans.line_input),
        (flows, "_ask", ans.ask),
        (flows, "_pick_detected_model", pick),
        (secret_prompt, "masked_secret_prompt", ans.secret),
        (mps, "_prompt_custom_api_mode_selection", api_mode_prompt),
        (builtins, "input", ans.input),
    ]
    saved = [(obj, name, getattr(obj, name)) for obj, name, _ in patches]
    buf = io.StringIO()
    error = None
    try:
        for obj, name, value in patches:
            setattr(obj, name, value)
        config = load_config()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            flows._model_flow_custom(config)
    except Exception as exc:  # noqa: BLE001
        error = f"{type(exc).__name__}: {exc}"
        buf.write(traceback.format_exc())
    finally:
        for obj, name, value in saved:
            setattr(obj, name, value)

    transcript = [REDACT(line) for line in buf.getvalue().splitlines() if line.strip()]
    # Read back what Hermes actually saved.
    cfg = load_config()
    model_cfg = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
    saved_model = str(model_cfg.get("default") or "")
    saved_url = str(model_cfg.get("base_url") or "")
    # load_config() expands ${VAR}; the raw file shows what Hermes actually wrote (a reference, not the key).
    key_ref = ""
    try:
        from hermes_cli.config import read_raw_config
        raw = read_raw_config()
        raw_model = raw.get("model") if isinstance(raw, dict) and isinstance(raw.get("model"), dict) else {}
        key_ref = str(raw_model.get("api_key") or "")
    except Exception:  # noqa: BLE001
        key_ref = "(unknown)" if model_cfg.get("api_key") else ""
    ok = (error is None and saved_model == ans.model and model_cfg.get("provider") == "custom"
          and saved_url.rstrip("/") != "")
    result = dict(
        trust=trust,
        model=saved_model,
        provider=str(model_cfg.get("provider") or ""),
        base_url=saved_url,
        api_mode=str(model_cfg.get("api_mode") or "auto"),
        key_reference=key_ref if key_ref.startswith("${") or key_ref == "(unknown)" else ("(inline)" if key_ref else ""),
        prompts=ans.asked,
        transcript=transcript,
    )
    if not ok:
        return emit(False, error="apply_failed", message=error or "Hermes did not save the expected model.", **result)
    return emit(True, **result)


def cmd_show(_req: dict) -> int:
    from hermes_cli.config import load_config
    cfg = load_config()
    model_cfg = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
    names = []
    for entry in cfg.get("custom_providers") or []:
        if isinstance(entry, dict) and str(entry.get("base_url") or "").rstrip("/") == str(model_cfg.get("base_url") or "").rstrip("/"):
            names.append(str(entry.get("name") or ""))
    return emit(True, model=str(model_cfg.get("default") or ""), provider=str(model_cfg.get("provider") or ""),
                base_url=str(model_cfg.get("base_url") or ""), display_name=(names[0] if names else ""))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["probe", "apply", "show"])
    parser.add_argument("--site-packages", default="")
    parser.add_argument("--repo", default="")
    args = parser.parse_args()
    try:
        req = read_request()
    except Exception as exc:  # noqa: BLE001
        return emit(False, error="bad_request", message=str(exc))
    real_stdout = sys.stdout
    try:
        setup_paths(args)
        # Anything a Hermes import prints must not break the single-line result protocol.
        noise = io.StringIO()
        with contextlib.redirect_stdout(noise):
            import hermes_cli  # noqa: F401
        return {"probe": cmd_probe, "apply": cmd_apply, "show": cmd_show}[args.command](req)
    except Exception as exc:  # noqa: BLE001
        sys.stdout = real_stdout
        return emit(False, error="exception", message=f"{type(exc).__name__}: {exc}",
                    trace=traceback.format_exc().splitlines()[-6:])


if __name__ == "__main__":
    sys.exit(main())
