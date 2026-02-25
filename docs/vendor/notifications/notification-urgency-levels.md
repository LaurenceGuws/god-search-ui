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

<a href="urgency-levels.html" class="single-crumb"><span
class="single-contents-icon"></span>Urgency Levels</a>

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

<span class="nav-inner"><span class="tool-label">Navigation</span><a href="categories.html" class="tool-spacer" accesskey="p"
title="6. Categories"><span class="prev-icon">←</span></a><a href="hints.html" class="tool-spacer" accesskey="n"
title="8. Hints"><span class="next-icon">→</span></a></span>

</div>

</div>

</div>

</div>

<div id="_fixed-header-wrap" class="inactive">

<div id="_fixed-header">

<div class="crumbs">

<a href="urgency-levels.html" class="single-crumb"><span
class="single-contents-icon"></span>Show Contents: Urgency Levels</a>

</div>

<div class="buttons">

<a href="#" class="top-button button">Top</a>

<div class="button">

<a href="categories.html" class="tool-spacer" accesskey="p"
title="6. Categories"><span class="prev-icon">←</span></a><a href="hints.html" class="tool-spacer" accesskey="n"
title="8. Hints"><span class="next-icon">→</span></a>

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

<div id="urgency-levels" class="sect1">

<div class="titlepage">

<div>

<div>

## <span class="number">7 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Urgency Levels</span> <a href="urgency-levels.html" class="permalink" title="Permalink">#</a>

</div>

</div>

</div>

Notifications have an urgency level associated with them. This defines
the importance of the notification. For example, "Joe Bob signed on"
would be a low urgency. "You have new mail" or "A USB device was
unplugged" would be a normal urgency. "Your computer is on fire" would
be a critical urgency.

Urgency levels are defined as follows:

<div id="id-1.8.4" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 3: </span><span class="name">Urgency Levels </span><a href="urgency-levels.html#id-1.8.4" class="permalink"
title="Permalink">#</a>

</div>

<div class="table-contents">

| Type | Description |
|------|-------------|
| 0    | Low         |
| 1    | Normal      |
| 2    | Critical    |

</div>

</div>

Developers must use their own judgement when deciding the urgency of a
notification. Typically, if the majority of programs are using the same
level for a specific type of urgency, other applications should follow
them.

For low and normal urgencies, server implementations may display the
notifications how they choose. They should, however, have a sane
expiration timeout dependent on the urgency level.

Critical notifications should not automatically expire, as they are
things that the user will most likely want to know about. They should
only be closed when the user dismisses them, for example, by clicking on
the notification.

</div>

</div>

<div class="page-bottom">

<div id="_bottom-navigation">

<a href="hints.html" class="nav-link"><span
class="next-icon">→</span><span class="nav-label">Hints</span></a><a href="categories.html" class="nav-link"><span
class="prev-icon">←</span><span class="nav-label">Categories</span></a>

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
