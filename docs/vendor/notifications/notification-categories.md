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

<a href="categories.html" class="single-crumb"><span
class="single-contents-icon"></span>Categories</a>

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

<span class="nav-inner"><span class="tool-label">Navigation</span><a href="icons-and-images.html" class="tool-spacer" accesskey="p"
title="5. Icons and Images"><span class="prev-icon">←</span></a><a href="urgency-levels.html" class="tool-spacer" accesskey="n"
title="7. Urgency Levels"><span class="next-icon">→</span></a></span>

</div>

</div>

</div>

</div>

<div id="_fixed-header-wrap" class="inactive">

<div id="_fixed-header">

<div class="crumbs">

<a href="categories.html" class="single-crumb"><span
class="single-contents-icon"></span>Show Contents: Categories</a>

</div>

<div class="buttons">

<a href="#" class="top-button button">Top</a>

<div class="button">

<a href="icons-and-images.html" class="tool-spacer" accesskey="p"
title="5. Icons and Images"><span class="prev-icon">←</span></a><a href="urgency-levels.html" class="tool-spacer" accesskey="n"
title="7. Urgency Levels"><span class="next-icon">→</span></a>

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

<div id="categories" class="sect1">

<div class="titlepage">

<div>

<div>

## <span class="number">6 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Categories</span> <a href="categories.html" class="permalink" title="Permalink">#</a>

</div>

</div>

</div>

Notifications can optionally have a type indicator. Although neither
client or nor server must support this, some may choose to. Those
servers implementing categories may use them to intelligently display
the notification in a certain way, or group notifications of similar
types.

Categories are in *`class.specific`* form. `class` specifies the generic
type of notification, and `specific` specifies the more specific type of
notification.

If a specific type of notification does not exist for your notification,
but the generic kind does, a notification of type *`class`* is
acceptable.

Third parties, when defining their own categories, should discuss the
possibility of standardizing on the hint with other parties, preferably
in a place such as the
<a href="http://freedesktop.org/mailman/listinfo/xdg" class="ulink"
target="_blank">xdg<span class="ulink-url">
(http://freedesktop.org/mailman/listinfo/xdg)</span></a> mailing list at
<a href="http://freedesktop.org/" class="ulink"
target="_blank">freedesktop.org<span class="ulink-url">
(http://freedesktop.org/)</span></a>. If it warrants a standard, it will
be added to the table above. If no consensus is reached, the category
should be in the form of "`x-`*`vendor`*`.`*`class`*`.`*`name`*."

The following table lists standard notifications as defined by this
spec. More will be added in time.

<div id="id-1.7.7" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 2: </span><span class="name">Categories </span><a href="categories.html#id-1.7.7" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

| Type | Description |
|----|----|
| `"call"` | A generic audio or video call notification that doesn't fit into any other category. |
| `"call.ended"` | An audio or video call was ended. |
| `"call.incoming"` | A audio or video call is incoming. |
| `"call.unanswered"` | An incoming audio or video call was not answered. |
| `"device"` | A generic device-related notification that doesn't fit into any other category. |
| `"device.added"` | A device, such as a USB device, was added to the system. |
| `"device.error"` | A device had some kind of error. |
| `"device.removed"` | A device, such as a USB device, was removed from the system. |
| `"email"` | A generic e-mail-related notification that doesn't fit into any other category. |
| `"email.arrived"` | A new e-mail notification. |
| `"email.bounced"` | A notification stating that an e-mail has bounced. |
| `"im"` | A generic instant message-related notification that doesn't fit into any other category. |
| `"im.error"` | An instant message error notification. |
| `"im.received"` | A received instant message notification. |
| `"network"` | A generic network notification that doesn't fit into any other category. |
| `"network.connected"` | A network connection notification, such as successful sign-on to a network service. This should not be confused with `device.added` for new network devices. |
| `"network.disconnected"` | A network disconnected notification. This should not be confused with `device.removed` for disconnected network devices. |
| `"network.error"` | A network-related or connection-related error. |
| `"presence"` | A generic presence change notification that doesn't fit into any other category, such as going away or idle. |
| `"presence.offline"` | An offline presence change notification. |
| `"presence.online"` | An online presence change notification. |
| `"transfer"` | A generic file transfer or download notification that doesn't fit into any other category. |
| `"transfer.complete"` | A file transfer or download complete notification. |
| `"transfer.error"` | A file transfer or download error. |

</div>

</div>

</div>

</div>

<div class="page-bottom">

<div id="_bottom-navigation">

<a href="urgency-levels.html" class="nav-link"><span
class="next-icon">→</span><span class="nav-label">Urgency
Levels</span></a><a href="icons-and-images.html" class="nav-link"><span
class="prev-icon">←</span><span class="nav-label">Icons and
Images</span></a>

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
