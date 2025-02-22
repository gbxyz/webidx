# webidx

webidx is a client-side search engine for static websites.

It works by using a simple Perl script ([webidx.pl](webidx.pl)) to generate an SQLite database containing an index of static HTML files. The SQLite database is then published alongside the static content.

The search functionality is implemented in [webidx.js](webidx.js) which uses [sql.js](https://github.com/sql-js/sql.js) to provide an interface to the SQLite file.

You can see a live demo of it [here](https://gavinbrown.xyz/webidx-demo/).

## How to use it

1. use [webidx.pl](webidx.pl) to generate the index:

```
$ /path/to/webidx.pl -x index.html -x archives.html --xP secret_files -o https://example.com -z . ./index.db
```

You can run `webidx.pl --help` to see all the available command-line options.

2. Include [sql.js](https://cdnjs.com/libraries/sql.js), [pako](https://cdnjs.com/libraries/pako) and [webidx.js](webidx.js) in your web page:

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.12.0/sql-wasm.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/pako/2.1.0/pako.min.js"></script>
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
* `resultCallback`: a callback which is passed an array of search results. Each result is an object with the `title` and `url` properties. If not defined, a modal dialog will be displayed.
* `errorCallback`: a callback which is passed any error string as an argument.
* `titleSuffix`: a string to be removed from the end of page titles.
* `titlePrefix`: a string to be removed from the beginning of page titles.
