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

<a href="basic-design.html" class="single-crumb"><span
class="single-contents-icon"></span>Basic Design</a>

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

<span class="nav-inner"><span class="tool-label">Navigation</span><a href="index.html" class="tool-spacer" accesskey="p"
title="Desktop Notifications Specification"><span
class="prev-icon">←</span></a><a href="backwards-compat.html" class="tool-spacer" accesskey="n"
title="3. Backwards Compatibility"><span class="next-icon">→</span></a></span>

</div>

</div>

</div>

</div>

<div id="_fixed-header-wrap" class="inactive">

<div id="_fixed-header">

<div class="crumbs">

<a href="basic-design.html" class="single-crumb"><span
class="single-contents-icon"></span>Show Contents: Basic Design</a>

</div>

<div class="buttons">

<a href="#" class="top-button button">Top</a>

<div class="button">

<a href="index.html" class="tool-spacer" accesskey="p"
title="Desktop Notifications Specification"><span
class="prev-icon">←</span></a><a href="backwards-compat.html" class="tool-spacer" accesskey="n"
title="3. Backwards Compatibility"><span class="next-icon">→</span></a>

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

<div id="basic-design" class="sect1">

<div class="titlepage">

<div>

<div>

## <span class="number">2 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Basic Design</span> <a href="basic-design.html" class="permalink" title="Permalink">#</a>

</div>

</div>

</div>

In order to ensure that multiple notifications can easily be displayed
at once, and to provide a convenient implementation, all notifications
are controlled by a single session-scoped service which exposes a D-BUS
interface.

On startup, a conforming implementation should take the
`org.freedesktop.Notifications` service on the session bus. This service
will be referred to as the "notification server" or just "the server" in
this document. It can optionally be activated automatically by the bus
process, however this is not required and notification server clients
must not assume that it is available.

The server should implement the `org.freedesktop.Notifications`
interface on an object with the path `"/org/freedesktop/Notifications"`.
This is the only interface required by this version of the
specification.

A notification has the following components:

<div id="id-1.3.6" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 1: </span><span class="name">Notification Components </span><a href="basic-design.html#id-1.3.6" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

<table class="table" data-summary="Notification Components"
data-border="1">
<thead>
<tr>
<th>Component</th>
<th>Description</th>
</tr>
</thead>
<tbody data-valign="top">
<tr>
<td data-valign="top">Application Name</td>
<td data-valign="top">This is the optional name of the application
sending the notification. This should be the application's formal name,
rather than some sort of ID. An example would be "FredApp E-Mail
Client," rather than "fredapp-email-client."</td>
</tr>
<tr>
<td data-valign="top">Replaces ID</td>
<td data-valign="top">An optional ID of an existing notification that
this notification is intended to replace.</td>
</tr>
<tr>
<td data-valign="top">Notification Icon</td>
<td data-valign="top">The notification icon. See <a
href="icons-and-images.html#icons-and-images-formats" class="xref"
title="5.2. Formats">Icons and Images Formats</a>.</td>
</tr>
<tr>
<td data-valign="top">Summary</td>
<td data-valign="top">This is a single line overview of the
notification. For instance, "You have mail" or "A friend has come
online". It should generally not be longer than 40 characters, though
this is not a requirement, and server implementations should word wrap
if necessary. The summary must be encoded using UTF-8.</td>
</tr>
<tr>
<td data-valign="top">Body</td>
<td data-valign="top"><p>This is a multi-line body of text. Each line is
a paragraph, server implementations are free to word wrap them as they
see fit.</p>
<p>The body may contain simple markup as specified in <a
href="markup.html" class="xref" title="4. Markup">Markup</a>. It must be
encoded using UTF-8.</p>
<p>If the body is omitted, just the summary is displayed.</p></td>
</tr>
<tr>
<td data-valign="top">Actions</td>
<td data-valign="top"><p>The actions send a request message back to the
notification client when invoked. This functionality may not be
implemented by the notification server, conforming clients should check
if it is available before using it (see the GetCapabilities message in
<a href="protocol.html" class="xref"
title="9. D-BUS Protocol">Protocol</a>). An implementation is free to
ignore any requested by the client. As an example one possible rendering
of actions would be as buttons in the notification popup.</p>
<p>Actions are sent over as a list of pairs. Each even element in the
list (starting at index 0) represents the identifier for the action.
Each odd element in the list is the localized string that will be
displayed to the user.</p>
<p>The default action (usually invoked by clicking the notification)
should have a key named <code class="literal">"default"</code>. The name
can be anything, though implementations are free not to display
it.</p></td>
</tr>
<tr>
<td data-valign="top">Hints</td>
<td data-valign="top"><p>Hints are a way to provide extra data to a
notification server that the server may be able to make use of.</p>
<p>See <a href="hints.html" class="xref" title="8. Hints">Hints</a> for
a list of available hints.</p></td>
</tr>
<tr>
<td data-valign="top">Expiration Timeout</td>
<td data-valign="top"><p>The timeout time in milliseconds since the
display of the notification at which the notification should
automatically close.</p>
<p>If -1, the notification's expiration time is dependent on the
notification server's settings, and may vary for the type of
notification.</p>
<p>If 0, the notification never expires.</p></td>
</tr>
</tbody>
</table>

</div>

</div>

Each notification displayed is allocated a unique ID by the server. This
is unique within the session. While the notification server is running,
the ID will not be recycled unless the capacity of a uint32 is exceeded.

This can be used to hide the notification before the expiration timeout
is reached. It can also be used to atomically replace the notification
with another. This allows you to (for instance) modify the contents of a
notification while it's on-screen.

</div>

</div>

<div class="page-bottom">

<div id="_bottom-navigation">

<a href="backwards-compat.html" class="nav-link"><span
class="next-icon">→</span><span class="nav-label">Backwards
Compatibility</span></a><a href="index.html" class="nav-link"><span
class="prev-icon">←</span><span class="nav-label">Desktop Notifications
Specification</span></a>

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
