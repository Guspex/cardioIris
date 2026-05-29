import json
import urllib.request
import urllib.error

ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"

SYSTEM_PROMPT = """
You are a cardiovascular surgical flow AI agent embedded in an IRIS interoperability pipeline.

You receive a FHIR Bundle containing Patient, Procedure, and Observation resources
for one patient. Your job is to:

1. Identify the patient's current surgical phase (AWAITING, IN_SURGERY, POST_OP)
2. Detect risk signals from scenario tags (EMERGENCY_ESCALATION, DELAYED_SURGERY, RECOVERY_ESCALATION)
3. Return a structured JSON recommendation with:
   - riskLevel: LOW | MEDIUM | HIGH | CRITICAL
   - recommendation: one clear action sentence
   - reasoning: brief clinical rationale (2-3 sentences)
   - suggestedNextStatus: the next expected phase
   - escalate: true/false

Respond ONLY with valid JSON. No markdown, no explanation outside the JSON object.
"""


def analyze_patient_bundle(fhir_bundle: dict, api_key: str) -> dict:
    if not api_key:
        return {
            "riskLevel": "UNKNOWN",
            "recommendation": "ANTHROPIC_API_KEY not configured.",
            "reasoning": "Set the ANTHROPIC_API_KEY environment variable to enable AI analysis.",
            "suggestedNextStatus": "",
            "escalate": False
        }

    user_message = (
        "Analyze this FHIR Bundle and return your assessment:\n\n"
        + json.dumps(fhir_bundle, indent=2)
    )

    payload = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 1024,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": user_message}]
    }

    req = urllib.request.Request(
        ANTHROPIC_API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01"
        },
        method="POST"
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        response_data = json.loads(resp.read().decode("utf-8"))

    raw_text = response_data["content"][0]["text"]
    return json.loads(raw_text)


def run_agent(patient_id: str, iris_api_base: str, api_key: str) -> dict:
    resources = []
    for resource_type in ["Patient", "Procedure", "Observation"]:
        url = f"{iris_api_base}/fhir/r4/{resource_type}?patient={patient_id}"
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/fhir+json"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("entry"):
                    resources.extend([e["resource"] for e in data["entry"]])
        except urllib.error.URLError:
            pass

    bundle = {
        "resourceType": "Bundle",
        "type": "collection",
        "entry": [{"resource": r} for r in resources]
    }

    return analyze_patient_bundle(bundle, api_key)


if __name__ == "__main__":
    import sys
    import os

    patient_id = sys.argv[1] if len(sys.argv) > 1 else "FHIR-TEST-001"
    iris_base = sys.argv[2] if len(sys.argv) > 2 else "http://localhost:52773"
    key = os.environ.get("ANTHROPIC_API_KEY", "")

    result = run_agent(patient_id, iris_base, key)
    print(json.dumps(result, indent=2))
