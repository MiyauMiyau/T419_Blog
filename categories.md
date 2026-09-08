---
layout: page
title: 카테고리
permalink: /categories/
---

{% assign sorted_categories = site.categories | sort %}
{% for category in sorted_categories %}
  {% assign name = category | first %}
  {% assign posts = category | last %}
  <h2 id="{{ name | slugify }}">{{ name }} <small>({{ posts | size }})</small></h2>
  <ul>
    {% for post in posts %}
    <li>
      <a href="{{ post.url | relative_url }}">{{ post.title }}</a>
      <span> — {{ post.date | date: "%Y-%m-%d" }}</span>
    </li>
    {% endfor %}
  </ul>
{% endfor %}
