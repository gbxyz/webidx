# webidx

webidx is a client-side search engine for static websites.

It works by using a simple [webidx.pl](webidx.pl) Perl script to generate an SQLite database of static HTML files. The SQLite database is then published alongside the static content.

The search functionality is implemented in [webidx.js](webidx.js) which uses [sql.js](https://github.com/sql-js/sql.js) to provide an interface to the SQLite file.

## How to use it

1. use [webidx.pl](webidx.pl) to generate the index:

```
$ /path/to/webidx.pl -x index.html -x archives.html -o https://example.com -z . ./index.db
```

You can run `webidx.pl --help` to see all the available command-line options.

2. Include [webidx.js](webidx.js) in your web page:

```html
<script src="/path/to/webidx.js"></script>
```

3. Create a search form:

```html
<form onsubmit="window.webidx.search({dbfile:'/webidx.db.gz',query:document.getElementById('q').value});return false;">
  <input id="q" type="search">
</form>
```

When the user hits the return key in the search box, a modal dialog will pop up containing search results!

The object that's passed to `window.webidx.search()` can have the following properties:

* `dbfile`: URL of the SQLite database file
* `query`: search query
* `errorCallback`: a callback which is passed any error string as an argument.
* `titleSuffix`: a string to be removed from the end of page titles.
* `titlePrefix`: a string to be removed from the beginning of page titles.
