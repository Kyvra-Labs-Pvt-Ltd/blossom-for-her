# OVA chat backend setup

## What is already in the Flutter app

- The dashboard has an **Ask OVA** entry that opens a new chat page.
- **Start a conversation** opens the expandable chat panel.
- Without a backend URL, OVA uses an offline keyword responder with a limited
  set of prepared replies. It is not an AI model and messages stay on-device.
- The client posts message history to `POST <CHAT_API_BASE_URL>/v1/chat`.
- The request is JSON: `{"messages":[{"role":"user","content":"..."}]}`.
- The response must be JSON with a non-empty string: `{"reply":"..."}`.
- Only chat messages are sent. The app does not attach the user's profile,
  cycle logs, or hormone data to the chat request, and it does not save chat
  history after the panel closes.
- No backend, model provider, or provider credential is configured in this
  project yet. Add a backend URL only when you want real model responses.

## What the backend needs to do

Create a server endpoint at `POST /v1/chat` that accepts the request above,
applies the health-safe instructions below on the server, calls the AI model,
and returns `{"reply":"the model response"}`. The server should reject malformed
or oversized requests and limit the amount of conversation history it accepts.

Keep the AI provider key in the backend's secret manager or environment. Do not
put it in Flutter code, assets, build arguments, or the response. Use HTTPS for
deployed services. Before real users use the feature, add appropriate
authentication, rate limits, privacy notice and consent, and a retention policy
for any logs or stored conversations. Avoid logging message contents by
default.

The app sends user and assistant turns to your endpoint. Add the system
instructions on the server; never accept a system instruction supplied by the
mobile client as authoritative.

## Suggested health-safe server instructions

> You are OVA, the conversational assistant for Blossom for Her, and a supportive source of general education about
> menstrual cycles and women's health. Be warm, respectful, nonjudgmental, and
> clear about uncertainty. Do not diagnose, claim certainty about a user's
> health, infer pregnancy or fertility from calendar estimates, or recommend
> starting, stopping, or changing medication or treatment. Do not treat cycle
> predictions or simulated hormone values as clinical measurements. Ask only
> relevant follow-up questions and do not request identifying information.
> Encourage a qualified healthcare professional for personalized advice or
> symptoms that are severe, persistent, new, worsening, or worrying. If a user
> describes a possible emergency, encourage them to contact local emergency
> services now. Do not minimize or dismiss symptoms. State plainly that you
> provide information, not medical diagnosis or a substitute for professional
> care.

Have a qualified women's-health clinician review the system instructions and
the resulting conversations before a public launch. For an example of
menstrual-bleeding symptoms that warrant emergency care, see
[ACOG's patient guidance on abnormal uterine bleeding](https://www.acog.org/womens-health/faqs/abnormal-uterine-bleeding).

## Connect a local backend

1. Start your backend on your computer. It must implement the contract above.
2. Pass its address while running Flutter. For an Android emulator that reaches
   a local service on port 8000, use:

   ```sh
   flutter run --dart-define=CHAT_API_BASE_URL=http://10.0.2.2:8000
   ```

   For iOS Simulator or a desktop browser, a local service is usually reachable
   at `http://localhost:8000`. The Flutter client allows plain HTTP only for
   these local development hosts; use HTTPS for a deployed backend or a
   physical device.

3. Open **Ask OVA**, expand the conversation, and send a test question.
   A successful backend response appears as Blossom's reply. A missing URL,
   network failure, or non-success response appears as an explanatory message.

For a deployed backend, replace the local URL with its HTTPS base URL:

```sh
flutter run --dart-define=CHAT_API_BASE_URL=https://your-backend.example
```

`CHAT_API_BASE_URL` is just the backend address, not a provider key. Flutter
compile-time values can be inspected in a built app, so only server-side code
should hold the model credential.
