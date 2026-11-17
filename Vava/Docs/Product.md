# Product scope

Current presentation: all product pages now render as local H5 inside a React Native initialized WKWebView. See [local H5 architecture and current acceptance](LocalH5Migration.md). Earlier React Native runtime evidence below describes the preceding renderer and does not establish H5 acceptance.

The application interface is packaged as local H5 and displayed by a React Native shell. TypeScript presentation modules render HTML and CSS through React Native for Web. Native iOS modules retain protected persistence, StoreKit, media and nearby communication. Current runtime acceptance is recorded in LocalH5Migration.md.

Vava follows Toli's five independent navigation stacks and its compact editorial layout. The main navigation opens on its first tab, Academy. The Release Bundle ID is `com.vava.pingpong`. Debug testing uses `im.seex.sao2` with the Yu Sun team.

| Screen | Behavior |
| --- | --- |
| Academy | Search and filter training courses. Tap the lesson area to open its details or the avatar and name to open its credited coaching source. The detail screen shows a single-line lesson title above the cover, below the navigation controls. Report lessons or block a coaching source from the lesson menu. Read public coaching links. Unlock original exercises once with coins, save courses, and complete practice steps. |
| Watch | Tap anywhere on a match card to open the replay details. Filter, save, read credits, and open the publisher's original replay with internet access. |
| Shorts | One real match recording at a time. Drag vertically to page through videos, expand search above the dimmed feed, tap the video to play or pause, double-tap to like, save, share, read Vava Editorial notes and add dated private comments or replies in half-height comments with playback underneath, visit publisher profiles, read credits, report clips, block publishers, and hide clips locally. Import videos through Photos and keep the copies on this device. |
| Chats | Show a welcome card when no conversations are visible. List pinned conversations first and order each group by latest activity. Swipe left to pin or unpin, mark read or unread, or delete a row from the inbox. Find nearby players, follow each other, and open a conversation with message history, a bottom composer, and voice and video call controls. |
| Me | View identity, engagement totals for local works, and the following count in one card. Swipe horizontally within the collection area or tap a label to switch between Shorts, Tutorials, Liked, and Saved. Practice progress appears under Tutorials. Edit identity, log out, or delete the account in Settings. Open Wallet to buy coin packs and review purchases and spending. |

Pull down at the top of a Vava screen to refresh. Scrollable pages show a temporary status indicator while the request runs. Shorts advances to a different available video, and content lists rotate eligible results within the current filter. Comments refresh private replies and rotate editorial notes. Details, forms, and empty states refresh their current data and acknowledge completion. Wallet refreshes the current storefront prices.

The Shorts player fills the page and fits each video at its original aspect ratio. The caption column aligns at the lower left and the action rail at the lower right. A single playback progress bar spans the width below both columns, above the tab bar when it is visible. During a vertical drag, the current page follows the gesture and reveals the neighboring clip's cover. Releasing a committed drag slides to that clip. Releasing a short drag returns the current clip to its original position. Pulling down at the first clip refreshes the feed.

Me updates its displayed wallet balance when verified purchases are saved, including deferred purchases completed while Me remains visible. Failed purchase delivery shows a persistent notice on Me and a retry card in Wallet. Opening or refreshing Wallet also checks unfinished purchases. Successful delivery clears that transaction's failure; other unresolved purchases retain their warning. Tutorials describes My learning and guides an empty library toward starting a lesson or unlocking a practice plan.

Use plain English for product actions, availability, and errors. Keep storage and development environment labels in engineering documentation. Describe private comments as private and keep editorial attribution visible.

The login screen, main tabs and in-app detail screens share a full-bleed illustration of an evergreen table tennis table, net, paddle and ball. Shorts uses its player surface. The owner-provided lime-and-black Vava logo is used for the launcher, login page and startup/error branding. The login logo fits within a 144-point square with its original proportions and colors. Kalam Bold is the display typeface. Comic Neue is the reading typeface. Third-party and operating-system surfaces control their own rendering.

Every cold launch opens the login screen with an unchecked agreement box, separate Terms of Service and Privacy Policy links, and a Log in button. Checking the box enables login to the on-device library. Agreement links open the owner-provided Google Docs. StoreKit and publisher links use their respective online services.

Wallet shows nine consumable coin packs in a three-column grid ordered by reference USD price. Accessibility text sizes use a single column. Choose an available pack, then tap Buy to open Apple's purchase sheet. Prices come from the current App Store storefront. Pull down to reload prices when an offer is unavailable.

Publisher profiles use the same card layout as Me for identity and counts. They show the credited source and use the same coaching photo as the lesson cards. Recording sources use a still from a credited work. Their engagement totals sum every clip credited to the same publisher. Following, blocking and private comments stay on this device. The Shorts and Tutorials labels switch between collections below the social actions. The flag opens reporting for a clip or lesson by that publisher. Message opens the conversation. When a publisher cannot reciprocate a follow, the action shows an explanation and adds it to the initiating profile's chat history. Manage blocked publishers in Settings.

Publisher and nearby player profiles place Follow and Message in equal-width buttons alongside a compact, equal-height Block icon. The icon exposes the Block or Unblock action to VoiceOver.
