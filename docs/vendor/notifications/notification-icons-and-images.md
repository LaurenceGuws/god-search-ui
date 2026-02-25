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

<a href="icons-and-images.html" class="single-crumb"><span
class="single-contents-icon"></span>Icons and Images</a>

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

<span class="nav-inner"><span class="tool-label">Navigation</span><a href="markup.html" class="tool-spacer" accesskey="p"
title="4. Markup"><span class="prev-icon">←</span></a><a href="categories.html" class="tool-spacer" accesskey="n"
title="6. Categories"><span class="next-icon">→</span></a></span>

</div>

</div>

</div>

</div>

<div id="_fixed-header-wrap" class="inactive">

<div id="_fixed-header">

<div class="crumbs">

<a href="icons-and-images.html" class="single-crumb"><span
class="single-contents-icon"></span>Show Contents: Icons and Images</a>

</div>

<div class="buttons">

<a href="#" class="top-button button">Top</a>

<div class="button">

<a href="markup.html" class="tool-spacer" accesskey="p"
title="4. Markup"><span class="prev-icon">←</span></a><a href="categories.html" class="tool-spacer" accesskey="n"
title="6. Categories"><span class="next-icon">→</span></a>

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

<div id="icons-and-images" class="sect1">

<div class="titlepage">

<div>

<div>

## <span class="number">5 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Icons and Images</span> <a href="icons-and-images.html" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

A notification can optionally have an associated icon and/or image.

The icon is defined by the "app_icon" parameter. The image can be
defined by the "image-path", the "image-data" hint or the deprecated
"icon_data" hint.

<div id="id-1.6.4" class="sect2">

<div class="titlepage">

<div>

<div>

### <span class="number">5.1 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Priorities</span> <a href="icons-and-images.html#id-1.6.4" class="permalink"
title="Permalink">#</a>

</div>

</div>

</div>

An implementation which only displays one image or icon must choose
which one to display using the following order:

<div class="orderedlist">

1.  "image-data"

2.  "image-path"

3.  app_icon parameter

4.  for compatibility reason, "icon_data"

</div>

An implementation which can display both the image and icon must show
the icon from the "app_icon" parameter and choose which image to display
using the following order:

<div class="orderedlist">

1.  "image-data"

2.  "image-path"

3.  for compatibility reason, "icon_data"

</div>

</div>

<div id="icons-and-images-formats" class="sect2">

<div class="titlepage">

<div>

<div>

### <span class="number">5.2 </span><span class="name" xmlns:dm="urn:x-suse:ns:docmanager">Formats</span> <a href="icons-and-images.html#icons-and-images-formats"
class="permalink" title="Permalink">#</a>

</div>

</div>

</div>

The "image-data" and "icon_data" hints should be a DBus structure of
signature (iiibiiay). The components of this structure are as follows:

<div class="orderedlist">

1.  width (i): Width of image in pixels

2.  height (i): Height of image in pixels

3.  rowstride (i): Distance in bytes between row starts

4.  has_alpha (b): Whether the image has an alpha channel

5.  bits_per_sample (i): Must always be 8

6.  channels (i): If has_alpha is TRUE, must be 4, otherwise 3

7.  data (ay): The image data, in RGB byte order

</div>

This image format is derived from
<a href="http://developer.gnome.org/gdk-pixbuf/stable/" class="ulink"
target="_blank">gdk-pixbuf<span class="ulink-url">
(http://developer.gnome.org/gdk-pixbuf/stable/)</span></a>.

The "app_icon" parameter and "image-path" hint should be either an URI
(file:// is the only URI schema supported right now) or a name in a
freedesktop.org-compliant icon theme (not a GTK+ stock ID).

</div>

</div>

</div>

<div class="page-bottom">

<div id="_bottom-navigation">

<a href="categories.html" class="nav-link"><span
class="next-icon">→</span><span class="nav-label">Categories</span></a><a href="markup.html" class="nav-link"><span
class="prev-icon">←</span><span class="nav-label">Markup</span></a>

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
