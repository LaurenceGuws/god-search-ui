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

<a href="hints.html" class="single-crumb"><span
class="single-contents-icon"></span>Hints</a>

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

<span class="nav-inner"><span class="tool-label">Navigation</span><a href="urgency-levels.html" class="tool-spacer" accesskey="p"
title="7. Urgency Levels"><span class="prev-icon">←</span></a><a href="protocol.html" class="tool-spacer" accesskey="n"
title="9. D-BUS Protocol"><span class="next-icon">→</span></a></span>

</div>

</div>

</div>

</div>

<div id="_fixed-header-wrap" class="inactive">

<div id="_fixed-header">

<div class="crumbs">

<a href="hints.html" class="single-crumb"><span
class="single-contents-icon"></span>Show Contents: Hints</a>

</div>

<div class="buttons">

<a href="#" class="top-button button">Top</a>

<div class="button">

<a href="urgency-levels.html" class="tool-spacer" accesskey="p"
title="7. Urgency Levels"><span class="prev-icon">←</span></a><a href="protocol.html" class="tool-spacer" accesskey="n"
title="9. D-BUS Protocol"><span class="next-icon">→</span></a>

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

<div id="hints" class="sect1">

<div class="titlepage">

<div>

<div>

## <span class="number">8 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Hints</span> <a href="hints.html" class="permalink" title="Permalink">#</a>

</div>

</div>

</div>

Hints are a way to provide extra data to a notification server that the
server may be able to make use of.

Neither clients nor notification servers are required to support any
hints. Both sides should assume that hints are not passed, and should
ignore any hints they do not understand.

Third parties, when defining their own hints, should discuss the
possibility of standardizing on the hint with other parties, preferably
in a place such as the
<a href="http://freedesktop.org/mailman/listinfo/xdg" class="ulink"
target="_blank">xdg<span class="ulink-url">
(http://freedesktop.org/mailman/listinfo/xdg)</span></a> mailing list at
<a href="http://freedesktop.org/" class="ulink"
target="_blank">freedesktop.org<span class="ulink-url">
(http://freedesktop.org/)</span></a>. If it warrants a standard, it will
be added to the table above. If no consensus is reached, the hint name
should be in the form of `"x-`*`vendor`*`-`*`name`*`."`

The value type for the hint dictionary in D-BUS is of the
`DBUS_TYPE_VARIANT` container type. This allows different data types
(string, integer, boolean, etc.) to be used for hints. When adding a
dictionary of hints, this type must be used, rather than putting the
actual hint value in as the dictionary value.

The following table lists the standard hints as defined by this
specification. Future hints may be proposed and added to this list over
time. Once again, implementations are not required to support these.

<div id="id-1.9.7" class="table">

<div class="table-title-wrap">

###### <span class="number">Table 4: </span><span class="name">Standard Hints </span><a href="hints.html#id-1.9.7" class="permalink" title="Permalink">#</a>

</div>

<div class="table-contents">

| Name               | Value Type |
|--------------------|------------|
| `"action-icons"`   | BOOLEAN    |
| `"category"`       | STRING     |
| `"desktop-entry"`  | STRING     |
| `"image-data"`     | (iiibiiay) |
| `"image_data"`     | (iiibiiay) |
| `"image-path"`     | STRING     |
| `"image_path"`     | STRING     |
| `"icon_data"`      | (iiibiiay) |
| `"resident"`       | BOOLEAN    |
| `"sound-file"`     | STRING     |
| `"sound-name"`     | STRING     |
| `"suppress-sound"` | BOOLEAN    |
| `"transient"`      | BOOLEAN    |
| `"x"`              | INT32      |
| `"y"`              | INT32      |
| `"urgency"`        | BYTE       |

</div>

</div>

</div>

</div>

<div class="page-bottom">

<div id="_bottom-navigation">

<a href="protocol.html" class="nav-link"><span
class="next-icon">→</span><span class="nav-label">D-BUS
Protocol</span></a><a href="urgency-levels.html" class="nav-link"><span
class="prev-icon">←</span><span class="nav-label">Urgency
Levels</span></a>

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
