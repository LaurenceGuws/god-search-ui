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

<a href="markup.html" class="single-crumb"><span
class="single-contents-icon"></span>Markup</a>

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

<span class="nav-inner"><span class="tool-label">Navigation</span><a href="backwards-compat.html" class="tool-spacer" accesskey="p"
title="3. Backwards Compatibility"><span class="prev-icon">←</span></a><a href="icons-and-images.html" class="tool-spacer" accesskey="n"
title="5. Icons and Images"><span class="next-icon">→</span></a></span>

</div>

</div>

</div>

</div>

<div id="_fixed-header-wrap" class="inactive">

<div id="_fixed-header">

<div class="crumbs">

<a href="markup.html" class="single-crumb"><span
class="single-contents-icon"></span>Show Contents: Markup</a>

</div>

<div class="buttons">

<a href="#" class="top-button button">Top</a>

<div class="button">

<a href="backwards-compat.html" class="tool-spacer" accesskey="p"
title="3. Backwards Compatibility"><span class="prev-icon">←</span></a><a href="icons-and-images.html" class="tool-spacer" accesskey="n"
title="5. Icons and Images"><span class="next-icon">→</span></a>

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

<div id="markup" class="sect1">

<div class="titlepage">

<div>

<div>

## <span class="number">4 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Markup</span> <a href="markup.html" class="permalink" title="Permalink">#</a>

</div>

</div>

</div>

Body text may contain markup. The markup is XML-based, and consists of a
small subset of HTML along with a few additional tags.

The following tags should be supported by the notification server.
Though it is optional, it is recommended. Notification servers that do
not support these tags should filter them out.

<div class="informaltable">

|                              |           |
|------------------------------|-----------|
| `<b>` ... `</b>`             | Bold      |
| `<i>` ... `</i>`             | Italic    |
| `<u>` ... `</u>`             | Underline |
| `<a href="...">` ... `</a>`  | Hyperlink |
| `<img src="..." alt="..."/>` | Image     |

</div>

A full-blown HTML implementation is not required of this spec, and
notifications should never take advantage of tags that are not listed
above. As notifications are not a substitute for web browsers or complex
dialogs, advanced layout is not necessary, and may in fact limit the
number of systems that notification services can run on, due to memory
usage and screen space. Such examples are PDAs, certain cell phones, and
slow PCs or laptops with little memory.

For the same reason, a full XML or XHTML implementation using XSLT or
CSS stylesheets is not part of this specification. Information that must
be presented in a more complex form should use an application-specific
dialog, a web browser, or some other display mechanism.

The tags specified above mark up the content in a way that allows them
to be stripped out on some implementations without impacting the actual
content.

<div id="hyperlinks" class="sect2">

<div class="titlepage">

<div>

<div>

### <span class="number">4.1 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Hyperlinks</span> <a href="markup.html#hyperlinks" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

Hyperlinks allow for linking one or more words to a URI. There is no
requirement to allow for images to be linked, and it is highly suggested
that implementations do not allow this, as there is no clean-looking,
standard visual indicator for a hyperlinked image.

Hyperlinked text should appear in the standard blue underline format.

Hyperlinks cannot function as a replacement for actions. They are used
to link to local directories or remote sites using standard URI schemes.

Implementations are not required to support hyperlinks.

</div>

<div id="images" class="sect2">

<div class="titlepage">

<div>

<div>

### <span class="number">4.2 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Images</span> <a href="markup.html#images" class="permalink" title="Permalink">#</a>

</div>

</div>

</div>

Images may be placed in the notification, but this should be done with
caution. The image should never exceed 200x100, but this should be
thought of as a maximum size. Images should always have alternative text
provided through the `alt="..."` attribute.

Image data cannot be embedded in the message itself. Images referenced
must always be local files.

Implementations are not required to support images.

</div>

</div>

</div>

<div class="page-bottom">

<div id="_bottom-navigation">

<a href="icons-and-images.html" class="nav-link"><span
class="next-icon">→</span><span class="nav-label">Icons and
Images</span></a><a href="backwards-compat.html" class="nav-link"><span
class="prev-icon">←</span><span class="nav-label">Backwards
Compatibility</span></a>

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
