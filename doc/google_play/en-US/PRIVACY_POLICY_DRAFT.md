# AI Link Privacy Policy (pre-publication draft)

Updated: October 31, 2026

**Before publication: add the legal developer/publisher name and public URL, then review against the final build and configured services.** Contact: mateolim93@gmail.com.

AI Link is a client for AI text and speech services configured by the user. It does not currently require an account or operate its own chat relay server.

## Data stored on devices

- API keys are stored in the phone's system secure storage. When selected service settings are sent to the watch, the watch stores the keys encrypted with Android Keystore.
- Provider settings, prompts, conversation titles and message content are stored in a local SQLite database on the phone. Message content and prompts are not separately encrypted in that database.
- Watch conversations may first be saved in the watch app's private storage and later sync to the phone's local history. Clearing phone data does not automatically delete offline watch data.
- Recordings and synthesized audio are temporary files used for requests and playback and deleted afterward. Transcribed text may be sent to the selected text model under your settings and saved in local chat history.

## Requests to third-party services

When you fetch a model list, send a message, transcribe speech or synthesize audio, the app sends the API key and the required context, prompts, recordings or speech text directly to the third-party API endpoint you configured. That provider's own policies and agreements determine how it processes and retains the data. Configure only providers you trust and review their privacy policies before sending sensitive information. AI Link does not upload this data to its own relay server.

When phone web search is enabled, the current question and search API key go directly to the selected search provider. Retrieved webpage content is then sent as temporary context to the current text model. Source links, titles and excerpts are saved with assistant replies in the unencrypted local SQLite database. The search toggle, selected service configuration and key sync automatically over the paired connection. Search keys remain in secure phone storage, Keystore-encrypted storage on Wear OS, or Keychain on Apple Watch. Watch requests use the same search-before-answer flow through the phone or the watch network; source links in answers sync back to the phone with chats. Deleting a search service deletes its key but keeps sources in existing chats; clearing all phone data removes both. Search is off by default. Testing search sends the fixed query “Flutter”, may incur charges and does not save the configuration.

Agent is off by default. After you enable it, tasks sent in chat, conversation history and attachments selected within the independent context budget, current project context, and required tool results are sent to your selected model. Model-generated queries go to your default search provider; public webpage requests connect directly to their websites. Goals, execution logs, evidence snapshots, and generated files are stored locally in plaintext. Tasks do not automatically update long-term memory. Deleting a task, its associated conversation or all local data removes the corresponding task records and files, but not copies you exported. Deleting only a task retains the delivered chat reply.

## Permissions

Microphone permission is used for voice recording you start by holding the button. Camera permission is used for scanning configuration and API key QR codes. Notification permission is used on Android to show that an Agent task is still running after the screen locks. Network access is used to contact configured providers and to synchronize data between phone and watch. Denying microphone, camera, or notification access does not prevent text chat.

## Deletion and contact

You can delete individual conversations or providers, or clear all phone data under Settings → General → Data and privacy. Uninstall the watch app to remove data stored on the watch. Deleting local data does not delete content previously sent to a third-party service; contact that provider to request deletion there.

For privacy questions, contact mateolim93@gmail.com.
