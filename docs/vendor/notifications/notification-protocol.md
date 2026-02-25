<div class="bypass-block">

[Jump to content](#_content)[Jump to page navigation: previous page
\[access key p\]/next page \[access key n\]](#_bottom-navigation)

</div>

<div id="_outer-wrap">

<div id="_white-bg">

<div id="_header">

<div id="_logo">

[![Freedesktop
Logo](static/images/logo.svg)](https://specifications.freedesktop.org/)

</div>

<div class="crumbs">

<a href="protocol.html" class="single-crumb"><span
class="single-contents-icon"></span>D-BUS Protocol</a>

<div class="bubble-corner active-contents">

</div>

</div>

<div class="clearme">

</div>

</div>

</div>

<div id="_toolbar-wrap">

<div id="_toolbar">

<div id="_toc-area" class="inactive">

<a href="index.html" id="_toc-area-button" class="tool" accesskey="c"
title="Contents"><span class="tool-spacer"><span
class="toc-icon">Contents</span><span
class="clearme"></span></span><span
class="tool-label">Contents</span></a>

<div class="active-contents bubble-corner">

</div>

<div class="active-contents bubble">

<div class="bubble-container">

###### Desktop Notifications Specification

<div id="_bubble-toc">

1.  [<span class="number">1
    </span><span class="name">Introduction</span>](index.html#introduction)
2.  [<span class="number">2 </span><span class="name">Basic
    Design</span>](basic-design.html)
3.  [<span class="number">3 </span><span class="name">Backwards
    Compatibility</span>](backwards-compat.html)
4.  [<span class="number">4
    </span><span class="name">Markup</span>](markup.html)
5.  [<span class="number">5 </span><span class="name">Icons and
    Images</span>](icons-and-images.html)
6.  [<span class="number">6
    </span><span class="name">Categories</span>](categories.html)
7.  [<span class="number">7 </span><span class="name">Urgency
    Levels</span>](urgency-levels.html)
8.  [<span class="number">8
    </span><span class="name">Hints</span>](hints.html)
9.  [<span class="number">9 </span><span class="name">D-BUS
    Protocol</span>](protocol.html)

</div>

<div class="clearme">

</div>

</div>

</div>

</div>

<div id="_nav-area" class="inactive">

<div class="tool">

<span class="nav-inner"><span class="tool-label">Navigation</span><a href="hints.html" class="tool-spacer" accesskey="p"
title="8. Hints"><span class="prev-icon">←</span></a><span class="tool-spacer"><span class="next-icon">→</span></span></span>

</div>

</div>

</div>

</div>

<div id="_fixed-header-wrap" class="inactive">

<div id="_fixed-header">

<div class="crumbs">

<a href="protocol.html" class="single-crumb"><span
class="single-contents-icon"></span>Show Contents: D-BUS Protocol</a>

</div>

<div class="buttons">

<a href="#" class="top-button button">Top</a>

<div class="button">

<a href="hints.html" class="tool-spacer" accesskey="p"
title="8. Hints"><span class="prev-icon">←</span></a><span class="tool-spacer"><span class="next-icon">→</span></span>

</div>

<div class="clearme">

</div>

</div>

<div class="clearme">

</div>

</div>

<div class="active-contents bubble">

<div class="bubble-container">

<div id="_bubble-toc">

1.  [<span class="number">1
    </span><span class="name">Introduction</span>](index.html#introduction)
2.  [<span class="number">2 </span><span class="name">Basic
    Design</span>](basic-design.html)
3.  [<span class="number">3 </span><span class="name">Backwards
    Compatibility</span>](backwards-compat.html)
4.  [<span class="number">4
    </span><span class="name">Markup</span>](markup.html)
5.  [<span class="number">5 </span><span class="name">Icons and
    Images</span>](icons-and-images.html)
6.  [<span class="number">6
    </span><span class="name">Categories</span>](categories.html)
7.  [<span class="number">7 </span><span class="name">Urgency
    Levels</span>](urgency-levels.html)
8.  [<span class="number">8
    </span><span class="name">Hints</span>](hints.html)
9.  [<span class="number">9 </span><span class="name">D-BUS
    Protocol</span>](protocol.html)

</div>

<div class="clearme">

</div>

</div>

</div>

</div>

<div id="_toc-bubble-wrap">

</div>

<div id="_content">

<div class="documentation">

<div id="protocol" class="sect1">

<div class="titlepage">

<div>

<div>

## <span class="number">9 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">D-BUS Protocol</span> <a href="protocol.html" class="permalink" title="Permalink">#</a>

</div>

</div>

</div>

The following messages <span class="emphasis">*must*</span> be supported
by all implementations.

<div id="commands" class="sect2">

<div class="titlepage">

<div>

<div>

### <span class="number">9.1 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Message commands</span> <a href="protocol.html#commands" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div id="command-get-capabilities" class="sect3">

<div class="titlepage">

<div>

<div>

#### <span class="number">9.1.1 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">`org.freedesktop.Notifications.GetCapabilities`</span> <a href="protocol.html#command-get-capabilities" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div class="funcsynopsis">

|                                                              |          |     |
|--------------------------------------------------------------|----------|-----|
| `as `**`org.freedesktop.Notifications.GetCapabilities`**` (` | `void)`; |     |

<div class="funcprototype-spacer">

 

</div>

</div>

This message takes no parameters.

It returns an array of strings. Each string describes an optional
capability implemented by the server. The following values are defined
by this spec:

<div id="id-1.10.3.2.5" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 5: </span><span class="name">Server Capabilities </span><a href="protocol.html#id-1.10.3.2.5" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

|  |  |
|----|----|
| `"action-icons"` | Supports using icons instead of text for displaying actions. Using icons for actions must be enabled on a per-notification basis using the "action-icons" hint. |
| `"actions"` | The server will provide the specified actions to the user. Even if this cap is missing, actions may still be specified by the client, however the server is free to ignore them. |
| `"body"` | Supports body text. Some implementations may only show the summary (for instance, onscreen displays, marquee/scrollers) |
| `"body-hyperlinks"` | The server supports hyperlinks in the notifications. |
| `"body-images"` | The server supports images in the notifications. |
| `"body-markup"` | Supports markup in the body text. If marked up text is sent to a server that does not give this cap, the markup will show through as regular text so must be stripped clientside. |
| `"icon-multi"` | The server will render an animation of all the frames in a given image array. The client may still specify multiple frames even if this cap and/or `"icon-static"` is missing, however the server is free to ignore them and use only the primary frame. |
| `"icon-static"` | Supports display of exactly 1 frame of any given image array. This value is mutually exclusive with `"icon-multi"`, it is a protocol error for the server to specify both. |
| `"persistence"` | The server supports persistence of notifications. Notifications will be retained until they are acknowledged or removed by the user or recalled by the sender. The presence of this capability allows clients to depend on the server to ensure a notification is seen and eliminate the need for the client to display a reminding function (such as a status icon) of its own. |
| `"sound"` | The server supports sounds on notifications. If returned, the server must support the `"sound-file"` and `"suppress-sound"` hints. |

</div>

</div>

New vendor-specific caps may be specified as long as they start with
`"x-`*`vendor`*`"`. For instance, `"x-gnome-foo-cap"`. Capability names
must not contain spaces. They are limited to alpha-numeric characters
and dashes (`"-"`).

</div>

<div id="command-notify" class="sect3">

<div class="titlepage">

<div>

<div>

#### <span class="number">9.1.2 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">`org.freedesktop.Notifications.Notify`</span> <a href="protocol.html#command-notify" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div class="funcsynopsis">

|  |  |
|----|----|
| `UINT32 `**`org.freedesktop.Notifications.Notify`**` (` | STRING `app_name`, |
|   | UINT32 `replaces_id`, |
|   | STRING `app_icon`, |
|   | STRING `summary`, |
|   | STRING `body`, |
|   | as `actions`, |
|   | a{sv} `hints`, |
|   | INT32 `expire_timeout``)`; |

<div class="funcprototype-spacer">

 

</div>

</div>

Sends a notification to the notification server.

<div id="id-1.10.3.3.4" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 6: </span><span class="name">Notify Parameters </span><a href="protocol.html#id-1.10.3.3.4" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

<table class="table" data-summary="Notify Parameters" data-border="1">
<thead>
<tr>
<th>Name</th>
<th>Type</th>
<th>Description</th>
</tr>
</thead>
<tbody data-valign="top">
<tr>
<td data-valign="top"><em>app_name</em></td>
<td data-valign="top">STRING</td>
<td data-valign="top">The optional name of the application sending the
notification. Can be blank.</td>
</tr>
<tr>
<td data-valign="top"><em>replaces_id</em></td>
<td data-valign="top">UINT32</td>
<td data-valign="top">The optional notification ID that this
notification replaces. The server must atomically (ie with no flicker or
other visual cues) replace the given notification with this one. This
allows clients to effectively modify the notification while it's active.
A value of value of 0 means that this notification won't replace any
existing notifications.</td>
</tr>
<tr>
<td data-valign="top"><em>app_icon</em></td>
<td data-valign="top">STRING</td>
<td data-valign="top">The optional program icon of the calling
application. See <a href="icons-and-images.html" class="xref"
title="5. Icons and Images">Icons and Images</a>. Can be an empty
string, indicating no icon.</td>
</tr>
<tr>
<td data-valign="top"><em>summary</em></td>
<td data-valign="top">STRING</td>
<td data-valign="top">The summary text briefly describing the
notification.</td>
</tr>
<tr>
<td data-valign="top"><em>body</em></td>
<td data-valign="top">STRING</td>
<td data-valign="top">The optional detailed body text. Can be
empty.</td>
</tr>
<tr>
<td data-valign="top"><em>actions</em></td>
<td data-valign="top">as</td>
<td data-valign="top">Actions are sent over as a list of pairs. Each
even element in the list (starting at index 0) represents the identifier
for the action. Each odd element in the list is the localized string
that will be displayed to the user.</td>
</tr>
<tr>
<td data-valign="top"><em>hints</em></td>
<td data-valign="top">a{sv}</td>
<td data-valign="top">Optional hints that can be passed to the server
from the client program. Although clients and servers should never
assume each other supports any specific hints, they can be used to pass
along information, such as the process PID or window ID, that the server
may be able to make use of. See <a href="hints.html" class="xref"
title="8. Hints">Hints</a>. Can be empty.</td>
</tr>
<tr>
<td data-valign="top"><em>expire_timeout</em></td>
<td data-valign="top">INT32</td>
<td data-valign="top"><p>The timeout time in milliseconds since the
display of the notification at which the notification should
automatically close.</p>
<p>If -1, the notification's expiration time is dependent on the
notification server's settings, and may vary for the type of
notification. If 0, never expire.</p></td>
</tr>
</tbody>
</table>

</div>

</div>

If *replaces_id* is 0, the return value is a UINT32 that represent the
notification. It is unique, and will not be reused unless a `MAXINT`
number of notifications have been generated. An acceptable
implementation may just use an incrementing counter for the ID. The
returned ID is always greater than zero. Servers must make sure not to
return zero as an ID.

If *replaces_id* is not 0, the returned value is the same value as
*replaces_id*.

</div>

<div id="command-close-notification" class="sect3">

<div class="titlepage">

<div>

<div>

#### <span class="number">9.1.3 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">`org.freedesktop.Notifications.CloseNotification`</span> <a href="protocol.html#command-close-notification" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div class="funcsynopsis">

|  |  |
|----|----|
| `void `**`org.freedesktop.Notifications.CloseNotification`**` (` | UINT32 `id``)`; |

<div class="funcprototype-spacer">

 

</div>

</div>

Causes a notification to be forcefully closed and removed from the
user's view. It can be used, for example, in the event that what the
notification pertains to is no longer relevant, or to cancel a
notification with no expiration time.

The `NotificationClosed` signal is emitted by this method.

If the notification no longer exists, an empty D-BUS Error message is
sent back.

</div>

<div id="command-get-server-information" class="sect3">

<div class="titlepage">

<div>

<div>

#### <span class="number">9.1.4 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">`org.freedesktop.Notifications.GetServerInformation`</span> <a href="protocol.html#command-get-server-information" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div class="funcsynopsis">

|  |  |
|----|----|
| ` void `**`org.freedesktop.Notifications.GetServerInformation`**` (` | out STRING `name`, |
|   | out STRING `vendor`, |
|   | out STRING `version`, |
|   | out STRING `spec_version``)`; |

<div class="funcprototype-spacer">

 

</div>

</div>

This message returns the information on the server. Specifically, the
server name, vendor, and version number.

<div id="id-1.10.3.5.4" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 7: </span><span class="name">GetServerInformation Return Values </span><a href="protocol.html#id-1.10.3.5.4" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

| Name           | Type   |
|----------------|--------|
| *name*         | STRING |
| *vendor*       | STRING |
| *version*      | STRING |
| *spec_version* | STRING |

</div>

</div>

</div>

</div>

<div id="signals" class="sect2">

<div class="titlepage">

<div>

<div>

### <span class="number">9.2 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Signals</span> <a href="protocol.html#signals" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div id="signal-notification-closed" class="sect3">

<div class="titlepage">

<div>

<div>

#### <span class="number">9.2.1 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">`org.freedesktop.Notifications.NotificationClosed`</span> <a href="protocol.html#signal-notification-closed" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div class="funcsynopsis">

|  |  |
|----|----|
| ` `**`org.freedesktop.Notifications.NotificationClosed`**` (` | UINT32 `id`, |
|   | UINT32 `reason``)`; |

<div class="funcprototype-spacer">

 

</div>

</div>

A completed notification is one that has timed out, or has been
dismissed by the user.

<div id="id-1.10.4.2.4" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 8: </span><span class="name">NotificationClosed Parameters </span><a href="protocol.html#id-1.10.4.2.4" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

| Name     | Type   |
|----------|--------|
| *id*     | UINT32 |
| *reason* | UINT32 |

</div>

</div>

The ID specified in the signal is invalidated
<span class="emphasis">*before*</span> the signal is sent and may not be
used in any further communications with the server.

</div>

<div id="signal-action-invoked" class="sect3">

<div class="titlepage">

<div>

<div>

#### <span class="number">9.2.2 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">`org.freedesktop.Notifications.ActionInvoked`</span> <a href="protocol.html#signal-action-invoked" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div class="funcsynopsis">

|  |  |
|----|----|
| ` `**`org.freedesktop.Notifications.ActionInvoked`**` (` | UINT32 `id`, |
|   | STRING `action_key``)`; |

<div class="funcprototype-spacer">

 

</div>

</div>

This signal is emitted when one of the following occurs:

<div class="itemizedlist">

- The user performs some global "invoking" action upon a notification.
  For instance, clicking somewhere on the notification itself.

- The user invokes a specific action as specified in the original Notify
  request. For example, clicking on an action button.

</div>

<div id="id-1.10.4.3.5" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 9: </span><span class="name">ActionInvoked Parameters </span><a href="protocol.html#id-1.10.4.3.5" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

| Name         | Type   |
|--------------|--------|
| *id*         | UINT32 |
| *action_key* | STRING |

</div>

</div>

<div id="id-1.10.4.3.6" class="admonition note normal">

<img src="static/images/icon-note.png" title="Note" class="symbol"
alt="Note" />

###### Note

Clients should not assume the server will generate this signal. Some
servers may not support user interaction at all, or may not support the
concept of being able to "invoke" a notification.

</div>

</div>

<div id="signal-activation-token" class="sect3">

<div class="titlepage">

<div>

<div>

#### <span class="number">9.2.3 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">`org.freedesktop.Notifications.ActivationToken`</span> <a href="protocol.html#signal-activation-token" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

<div class="funcsynopsis">

|  |  |
|----|----|
| ` `**`org.freedesktop.Notifications.ActivationToken`**` (` | UINT32 `id`, |
|   | STRING `activation_token``)`; |

<div class="funcprototype-spacer">

 

</div>

</div>

This signal can be emitted before a `ActionInvoked` signal. It carries
an activation token that can be used to activate a toplevel.

<div id="id-1.10.4.4.4" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 10: </span><span class="name">ActivationToken Parameters </span><a href="protocol.html#id-1.10.4.4.4" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

| Name               | Type   |
|--------------------|--------|
| *id*               | UINT32 |
| *activation_token* | STRING |

</div>

</div>

<div id="id-1.10.4.4.5" class="admonition note normal">

<img src="static/images/icon-note.png" title="Note" class="symbol"
alt="Note" />

###### Note

Clients should not assume the server will generate this signal. Some
servers may not support user interaction at all, or may not support the
concept of being able to generate an activation token for a
notification.

</div>

</div>

</div>

</div>

</div>

<div class="page-bottom">

<div id="_bottom-navigation">

<a href="hints.html" class="nav-link"><span
class="prev-icon">←</span><span class="nav-label">Hints</span></a>

</div>

</div>

</div>

<div id="_inward">

</div>

</div>

<div id="_footer-wrap">

<div id="_footer">

© 2026 Freedesktop.org

</div>

</div>
