# AI Link Privacy Policy (pre-publication draft)

Updated: September 29, 2026

**Before publication: add the legal developer/publisher name and public URL, then review against the final build and configured services.** Contact: mateolim93@gmail.com.

AI Link is a client for AI text and speech services configured by the user. It does not currently require an account or operate its own chat relay server.

## Data stored on devices

- API keys are stored in the phone's system secure storage. When selected service settings are sent to the watch, the watch stores the keys encrypted with Android Keystore.
- Provider settings, prompts, conversation titles and message content are stored in a local SQLite database on the phone. Message content and prompts are not separately encrypted in that database.
- Watch conversations may first be saved in the watch app's private storage and later sync to the phone's local history. Clearing phone data does not automatically delete offline watch data.
- Recordings and synthesized audio are temporary files used for requests and playback and deleted afterward. Transcribed text may be sent to the selected text model under your settings and saved in local chat history.

## Requests to third-party services

When you fetch a model list, send a message, transcribe speech or synthesize audio, the app sends the API key and the required context, prompts, recordings or speech text directly to the third-party API endpoint you configured. That provider's own policies and agreements determine how it processes and retains the data. Configure only providers you trust and review their privacy policies before sending sensitive information. AI Link does not upload this data to its own relay server.

## Permissions

Microphone permission is used for voice recording you start by holding the button. Camera permission is used for scanning configuration and API key QR codes. Network access is used to contact configured providers and to synchronize data between phone and watch. Denying microphone or camera access does not prevent text chat.

## Deletion and contact

You can delete individual conversations or providers, or clear all phone data under Settings → Model settings → Data and privacy. Uninstall the watch app to remove data stored on the watch. Deleting local data does not delete content previously sent to a third-party service; contact that provider to request deletion there.

For privacy questions, contact mateolim93@gmail.com.
