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

<a href="backwards-compat.html" class="single-crumb"><span
class="single-contents-icon"></span>Backwards Compatibility</a>

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

<span class="nav-inner"><span class="tool-label">Navigation</span><a href="basic-design.html" class="tool-spacer" accesskey="p"
title="2. Basic Design"><span class="prev-icon">←</span></a><a href="markup.html" class="tool-spacer" accesskey="n"
title="4. Markup"><span class="next-icon">→</span></a></span>

</div>

</div>

</div>

</div>

<div id="_fixed-header-wrap" class="inactive">

<div id="_fixed-header">

<div class="crumbs">

<a href="backwards-compat.html" class="single-crumb"><span
class="single-contents-icon"></span>Show Contents: Backwards
Compatibility</a>

</div>

<div class="buttons">

<a href="#" class="top-button button">Top</a>

<div class="button">

<a href="basic-design.html" class="tool-spacer" accesskey="p"
title="2. Basic Design"><span class="prev-icon">←</span></a><a href="markup.html" class="tool-spacer" accesskey="n"
title="4. Markup"><span class="next-icon">→</span></a>

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

<div id="backwards-compat" class="sect1">

<div class="titlepage">

<div>

<div>

## <span class="number">3 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Backwards Compatibility</span> <a href="backwards-compat.html" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

Clients should try and avoid making assumptions about the presentation
and abilities of the notification server. The message content is the
most important thing.

Clients can check with the server what capabilities are supported using
the `GetCapabilities` message. See <a href="protocol.html" class="xref"
title="9. D-BUS Protocol">Protocol</a>.

If a client requires a response from a passive popup, it should be coded
such that a non-focus-stealing message box can be used in the case that
the notification server does not support this feature.

</div>

</div>

<div class="page-bottom">

<div id="_bottom-navigation">

<a href="markup.html" class="nav-link"><span
class="next-icon">→</span><span class="nav-label">Markup</span></a><a href="basic-design.html" class="nav-link"><span
class="prev-icon">←</span><span class="nav-label">Basic
Design</span></a>

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
