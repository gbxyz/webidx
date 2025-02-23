window.webidx = {};
const webidx = window.webidx;

webidx.search = async function (params) {
  if (!webidx.sql) {
    //
    // initialise sql.js
    //
    webidx.sql = await window.initSqlJs({locateFile: file => `https://sql.js.org/dist/${file}`});
  }

  if (webidx.hasOwnProperty("db")) {
    webidx.displayResults(webidx.query(params.query), params);

  } else {
    webidx.loadDB(params);

  }
};

webidx.loadDB = function (params) {
  const xhr = new XMLHttpRequest();

  xhr.open("GET", params.dbfile);
  xhr.timeout = params.timeout ?? 5000;
  xhr.responseType = "arraybuffer";

  xhr.ontimeout = function() {
    if (params.hasOwnProperty("errorCallback")) {
      params.errorCallback("Unable to load index, please refresh the page.");
    }
  };

  xhr.onload = function() {
    webidx.initializeDB(this.response);
    const results = webidx.query(params.query);
    webidx.displayResults(results, params);
  };

  xhr.send();
};

webidx.initializeDB = function (arrayBuffer) {
  webidx.db = new webidx.sql.Database(window.pako.inflate(new Uint8Array(arrayBuffer)));
};

webidx.query = function (query) {
  //
  // search results
  //
  let pages = [];

  //
  // split the search term into words
  //
  const words = query.trim().toLowerCase().split(" ");

  let queryBuffer = [];
  for (var i = 0 ; i < words.length ; i++) {
    queryBuffer.push(`SELECT page_id,SUM(hits) AS hits FROM \`index\`,words WHERE (word_id=words.id AND word=:word${i}) GROUP BY page_id`);
  }

  const sth = webidx.db.prepare(
    "SELECT pages.*,page_id,SUM(hits) AS hits FROM ("
    + queryBuffer.join(" UNION ")
    + ") JOIN pages ON pages.id=page_id GROUP BY page_id ORDER BY hits DESC"
  );

  sth.bind(words);

  while (sth.step()) {
    pages.push(sth.getAsObject());
  }

  return pages;
};

webidx.regExpQuote = function (str) {
  return str.replace(/[/\-\\^$*+?.()|[\]{}]/g, "\\$&");
};

webidx.displayResults = function (pages, params) {
  var callback = params.resultCallback ?? webidx.displayDialog;
  callback(pages, params);
};

webidx.displayDialog = function (pages, params) {
  var dialog = document.createElement("dialog");
  dialog.classList.add("webidx-results-dialog")

  dialog.appendChild(document.createElement("h2")).appendChild(document.createTextNode("Search Results"));

  if (pages.length < 1) {
    dialog.appendChild(document.createElement("p")).appendChild(document.createTextNode("Nothing found."));

  } else {
    var ul = dialog.appendChild(document.createElement("ul"));

    pages.forEach(function(page) {
      var titleText = page.title;

      if (params.titleSuffix) {
        titleText = titleText.replace(new RegExp(webidx.regExpQuote(params.titleSuffix)+"$"), "");
      }

      if (params.titlePrefix) {
        titleText = titleText.replace(new RegExp("^" + webidx.regExpQuote(params.titleSuffix)), "");
      }

      var li = ul.appendChild(document.createElement("li"));
      var a = li.appendChild(document.createElement("a"));
      a.setAttribute("href", page.url);
      a.appendChild(document.createTextNode(titleText));
      li.appendChild(document.createElement("br"));

      var span = li.appendChild(document.createElement("span"));
      span.classList.add("webidx-page-url");
      span.appendChild(document.createTextNode(page.url));
    });
  }

  var form = dialog.appendChild(document.createElement("form"));
  form.setAttribute("method", "dialog");

  var button = form.appendChild(document.createElement("button"));
  button.setAttribute("autofocus", true);
  button.appendChild(document.createTextNode("Close"));

  document.body.appendChild(dialog);

  dialog.addEventListener("close", function() {
    dialog.parentNode.removeChild(dialog);
  });

  dialog.showModal();
  dialog.scrollTop = 0;
};
