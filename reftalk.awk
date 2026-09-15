#!/usr/local/bin/gawk -bE   

#
# Talk pages needing a {{reflist-talk}}
#
#  https://github.com/greencardamom/Reftalk
#

# The MIT License (MIT)
#
# Copyright (c) 2019-2026 by User:GreenC (at en.wikipedia.org)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

BEGIN { # Bot cfg

  _defaults = "home      = /home/greenc/toolforge/reftalk/ \
               emailfp   = /home/greenc/scripts/secrets/greenc.email \
               userid    = User:GreenC \
               version   = 2.0 \
               copyright = 2026"

  asplit(G, _defaults, "[ ]*[=][ ]*", "[ ]{9,}")
  BotName = "reftalk"
  Home = G["home"]
  Engine = 3

  # Agent string format non-compliance could result in 429 (too many requests) rejections by WMF API
  Agent = BotName "-" G["version"] "-" G["copyright"] " (" G["userid"] "; mailto:" strip(readfile(G["emailfp"])) ")"

  IGNORECASE = 1

  G["dat"]    = G["home"] "dat/"
  G["static"] = G["home"] "static/"
  G["log"]    = G["home"] "log/"

  # ---- per-wiki. Everything below changes if this is not en.wikipedia ----

  G["hostname"] = "en"              # wikiget -l target
  G["domain"]   = "wikipedia.org"

  # The template the bot adds, and the page credited in its edit summaries. Both appear
  # in what readers see, so set them before running anywhere
  G["template"] = "reflist-talk"
  G["botpage"]  = "User:GreenC bot/Job 8"

  # Titles already in a talk namespace, which are worked on directly rather than via
  # their Talk: page. These are the English namespace names - a different language wiki
  # needs its own (de: "Wikipedia Diskussion:|Benutzer Diskussion:")
  G["re1"]    = "^(Wikipedia talk[:]|User talk[:])"

  # ---- not normally changed ----

  G["fqdn"]     = G["hostname"] "." G["domain"]
  G["apiurl"]   = "https://" G["fqdn"] "/w/api.php?"
  G["apitries"] = 3                 # apiget() attempts. Keep low - wikiget retries internally
  G["maxlag"]   = 5
  G["apibatch"] = 500               # titles per API request. 500 is the apihighlimits ceiling

  # A rendered reference list. Matches Parsoid (class="mw-references references", what
  # /wiki/ serves and readers see) and the legacy parser (class="references"), with or
  # without JSON's backslash-escaped quotes. Do not anchor on the closing ">" - Parsoid
  # emits id=, typeof= and data-mw= attributes after the class.
  G["reflist"] = "<[ ]*ol[ ]*class[ ]*[=][ ]*[\\\\]?\"(mw-references )?references[\\\\]?\""

  # Timestamp when the program last ran. Generate via:
  #  awk -ilibrary 'BEGIN{s = "20210201"; print strftime("%s", mktime(substr(s, 1, 4) " " substr(s, 5, 2) " " substr(s, 7, 2) " 0 0 0"), 1)}'

  # 2025-09-01  (timestamp of the old all-pages file)
  G["laststamp"] = "1756717200"

  # cron-reftalk.awk writes dat/laststamp from the mtime of the list it is replacing,
  # so an automated cycle does not need this file edited by hand
  if(checkexists(G["dat"] "laststamp"))
    G["laststamp"] = strip(readfile(G["dat"] "laststamp"))

}

@include "botwiki.awk"
@include "library.awk"
@include "atools.awk"
@include "json.awk"

BEGIN {

  loadtemplates()

  main()

  exit 0

}

function main(  i,a,j,bz,sz,ez,sp,z,command,dn,bm,la,startpoint,offset,endall,bl,article,al,artblock,c,stamp,wikisrc,ls,apiname,fp) {

  # batch mode. 0 = for testing small batch or single page. 1 = for production of all-pages
  bm = 1
  
  if(bm == 0) {

    # Single page mode. Set to 0 to disable single page mode, or set to name of article
    # sp = "Wikipedia talk:Bots/Requests for approval/GreenC bot 8"
    # sp = "Hydraulic fracturing by country"
    sp = 0

    # batch size. 1000 default
    bz = 1000  

    # Start location. Set sz = "0" for first batch, "1000" for second etc..                
    sz = 130000     

    # End location. Set ez = "1000" for first batch, "2000" for second etc..
    ez = 200000

    for(z = sz + 1; z <= ez; z = z + bz) {

      if(!sp) { # batch mode

        CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

        command = Exe["tail"] " -n +" z " " G["dat"] "all-pages | " Exe["head"] " -n " bz " > " G["dat"] "runpages.new"
        sys2var(command)

        dn = z "-" z + (bz - 1)
        print dn " of " ez " " CurTime >> G["log"] "batch-done"
        close(G["log"] "batch-done")
      
        if( checkexists(G["dat"] "runpages.new") ) {
          for(i=1; i <= splitn(G["dat"] "runpages.new", a, i); i++) {
            # stdErr("Processing " a[i])
            reftalk(getrendered(a[i]), a[i])
          }
        }
      }

      else {  # single page mode

        CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

        reftalk(getrendered(sp), sp)
        exit 0
      }
    }
  }
  
  # Run all-pages
  #  Below method of processing all-pages (5+ million lines) is designed to minimize memory on Toolforge grid, 
  #  keep log files small, and gracefully handles frequent stops by the grid. But also works on any server.
  #   all-pages = file containing complete list of millions of article titles. See setup instructions.
  #   all-pages.done = permanent log. One line equates to 1000 articles processed.
  #   all-pages.offset = temporary log. One line equates to one article processed. This resets to 0-len with
  #                      each new 1000 block. If the bot halts mid-way through, it will pick up where left off.

  else if(bm == 1) {  

    # Establish startpoint ie. the line number in all-pages where processing will begin 

    # To manually set startpoint. Set along a 1000 boundary ending in 1 eg. 501001 OK. 501100 !OK
    # startpoint = 202001

    # To auto start where it left-off, use last entry in all-pages.done as block startpoint
    if(empty(startpoint) && checkexists(G["log"] "all-pages.done")) {
      startpoint = sys2var(Exe["tail"] " -n 1 " G["log"] "all-pages.done | " Exe["grep"] " -oE \"^[^-]*[^-]\"")

      if(startpoint ~ /endall/) {    # reached the end
        email(Exe["from_email"], Exe["to_email"], "NOTIFY: " BotName " already reached the end. Aborted run.", "")
        exit 0
      }

      if(!isanumber(startpoint)) {  # log corrupted
        email(Exe["from_email"], Exe["to_email"], "NOTIFY: " BotName " unable to restart", "")
        exit 0
      }

      CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")
      print CurTime " ---- Bot (re)start (" startpoint "-" startpoint + 999 ")" >> G["log"] "restart"
      close(G["log"] "restart")
    }

    # All else fails (eg. first run) start at 1
    if(empty(startpoint))
      startpoint = 1

    if (checkexists(G["dat"] "all-pages") ) {

      # Check for offset ie. bot previously halted mid-way through a block
      if (checkexists(G["log"] "all-pages.offset")) {
        offset = int(sys2var(Exe["tail"] " -n 1 " G["log"] "all-pages.offset"))
        if(offset == 0)
          offset = 1
        if(offset == 999 || offset == 1000)
          offset = 998
        removefile2(G["log"] "all-pages.offset")
      }
      else
        offset = 1

      # Iterate through all-pages creating blocks of 1000 articles each
      for(bl = startpoint; bl > 0; bl += 1000) {

        # Retrieve a 1000 block from all-pages - unix tail/head is most efficient 
        artblock = sys2var(Exe["tail"] " -n +" bl " " G["dat"] "all-pages | " Exe["head"] " -n 1000")

        # Reached the end of all-pages?
        if(length(artblock) < 1000)
          endall = 1

        # Log the block at all-pages.done
        CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")
        print bl "-" bl+999 " " CurTime >> G["log"] "all-pages.done"
        close(G["log"] "all-pages.done")

        c = splitn(artblock "\n", article)

        # Timestamps for the whole block, then wikitext for those that pass, 500 titles
        # a request instead of one request per article
        batchstamps(article, offset, c, stamp)
        batchcontent(article, offset, c, stamp, wikisrc)

        # Iterate through the 1..1000 individual articles in artblock
        for(al = offset; al <= c; al++) {

          # Log to offset file
          print al >> G["log"] "all-pages.offset"
          close(G["log"] "all-pages.offset")

          # Log debug file (optional)
          # print bl "-" bl+999 " " al >> G["log"] "all-pages.debug"
          # close(G["log"] "all-pages.debug")

          apiname = apititle(article[al])

          # Skip if page has not been edited since last time bot ran
          ls = stamp[apiname]
          if(!empty(ls) && ls != 0) {
            if( int(ls) < int(G["laststamp"])) {
              continue
            }
          }
          else { # No talk page, or the request failed
            print "Warning laststamp: missing talk page (" apiname ") ---- " CurTime >> G["log"] "syslog"
            close(G["log"] "syslog")
            continue
          }

          # A title absent from wikisrc means its request failed. Skipping silently
          # would drop the article for good - the block is already marked done
          if(!(apiname in wikisrc)) {
            print "Warning batchcontent: no content for (" apiname ") ---- " CurTime >> G["log"] "syslog"
            close(G["log"] "syslog")
            continue
          }

          # Without a <ref> nothing can render a reference list, so reftalk() would
          # abort on HTML that has not been fetched yet
          fp = wikisrc[apiname]
          if(index(fp, "<ref") == 0)
            continue

          # Run bot on given article title
          reftalk(getrendered(article[al]), article[al], fp)
        }

        # Successful completion of 1000 articles, clear offset file
        removefile2(G["log"] "all-pages.offset")
        offset = 1
 
        # Reached end of all-pages, quit
        if(endall) {
          print "endall" >> G["log"] "all-pages.done"
          break
        }
      }
    }
    email(Exe["from_email"], Exe["to_email"], "NOTIFY: " BotName " has completed processing all articles!", "")
  }
}

#
# Determine if there is a missing reflist template anywhere on the page
#
#  wikihtml is the rendered page, as the raw action=parse JSON from getrendered().
#  It is used only to count rendered reference lists, so the JSON is never parsed -
#  G["reflist"] tolerates JSON's escaped quotes and matches the markup either way.
#
function reftalk(wikihtml, wikiname, wikisource,   tfp,i,j,k,l,fp) {

  tfp = stripwikicomments(wikihtml)
  j = gsub(G["reflist"], "", tfp)
  if(j == 0)           # abort early - no refs on page
    return 0

  # batchcontent() already has it in the all-pages path; single page mode does not
  if(!empty(wikisource))
    fp = wikisource
  else
    fp = sys2var(Exe["wikiget"] " -w " shquote(apititle(wikiname)) )

  tfp = stripnowikicom(fp)
  if(gsub(G["templates"], "", tfp) < j) {
    addreftalk(fp, wikiname)
    return 1
  }
  return 0

}

#
# Go through each section checking for the canidate 
#
function addreftalk(wikisource, wikiname,    jsoninTOC,jsonaTOC,arrTOC,jsoninSecW,jsonaSecW,arrSecW,s,a,mid,i,out,summary,edcnt,origWS,origSec,apiname,b,nempty,remcnt) {

  if(wikiname !~ G["re1"]) 
    apiwikiname = "Talk:" wikiname
  else 
    apiwikiname = wikiname

  # Get index of sections, then step through each one looking for a missing {{relist}} in the content

  jsoninTOC = apiget(G["apiurl"] "action=parse&page=" urlencodeawk(apiwikiname) "&prop=sections&format=json&formatversion=2&maxlag=" G["maxlag"])

  if( query_json(jsoninTOC, jsonaTOC) >= 0) {

    # awkenough_dump(jsonaTOC, "jsonaTOC")
    # jsona["parse","sections","2","line"]=Please do not "correct" the statement about universal donors

    splitja(jsonaTOC, arrTOC, 3, "line")

    for(s in arrTOC) {

      if(jsonaTOC["parse","sections",s,"toclevel"] != 1) continue # skip if not a 1st level section ie. == <section> == 

      jsoninSecW = apiget(G["apiurl"] "action=query&prop=revisions&rvprop=content&rvslots=main&rvlimit=1&titles=" urlencodeawk(apiwikiname) "&rvsection=" s "&format=json&formatversion=2&maxlag=" G["maxlag"])

      if( query_json(jsoninSecW, jsonaSecW) >= 0) {

        # awkenough_dump(jsonaSecW, "jsonaSecW")
        # jsona2["query","pages","1","revisions","1","slots","main","content"]=

        splitja(jsonaSecW, arrSecW, 5, "content")

        # print "title   = " arrTOC[s]
        # print "content = " arrSecW["1"]

        if(match(stripnowikicom(arrSecW["1"]), /[<][ ]*ref[ ]*/) && match(stripnowikicom(arrSecW["1"]), /[<][ ]*\/[ ]*ref[ ]*[>]/) && ! match(stripnowikicom(arrSecW["1"]), G["templates"]) ) {

          CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

          # Remove empty <ref></ref>. Only the unnamed form: it names nothing so it can
          # never be a reuse, and renders as a Cite error. <ref name="x"></ref> is left
          # alone - that one reuses a definition elsewhere on the page
          origSec = arrSecW["1"]
          nempty = gsub(/[<][ ]*ref[ ]*[>][ \t\n]*[<][ ]*[\/][ ]*ref[ ]*[>]/, "", arrSecW["1"])

          # Nothing left to list once they are gone - write the removal and move on
          if(!match(stripnowikicom(arrSecW["1"]), /[<][ ]*ref[ ]*/)) {
            if(nempty > 0) {
              origWS = wikisource
              wikisource = gsubs(origSec, arrSecW["1"], wikisource)
              if(origWS == wikisource) {
                print wikiname " ---- " CurTime " ---- gsubs() failure on empty <ref></ref> in section \"" arrTOC[s] "\"" >> G["log"] "error"
                close(G["log"] "error")
              }
              else
                remcnt += nempty
            }
            continue
          }

          # Check for a level-1 section that umbrellas in all level-2's below it - log and skip
          splitn(arrSecW["1"] "\n", b)
          if(b[1] ~ /[^=][=]$/) {
            print wikiname " ---- " CurTime " ---- Level-1 error in section \"" arrTOC[s] "\"" >> G["log"] "error"
            continue
          }

          # Determine if line-break needed between body of text and template
          i = splitn(arrSecW["1"], a)
          if(empty(a[i])) 
            mid = ""
          else
            mid = "\n"

          # Add the template, check and log if error. Search on origSec - wikisource
          # still holds the section as it was before the empty refs came out
          out = arrSecW["1"] mid "\n{{" G["template"] "}}"
          origWS = wikisource
          wikisource = gsubs(origSec, out, wikisource)
          if(origWS == wikisource) {
            print wikiname " ---- " CurTime " ---- gsubs() failure" >> G["log"] "error"
            continue
          }
          edcnt++
          remcnt += nempty

          # mis-match caused by transclusions
          if( ! match(arrSecW["1"], "[=]{1,2}[ ]*" regesc3(arrTOC[s]))) { 
            arrTOC[s] = strip(a[1])
            gsub(/^[=]{1,2}[ ]*|[ ]*[=]{1,2}$/, "", arrTOC[s])
          }

          # remove any "[[" and "]]" in title#sectionname otherwise it renders incorrectly
          gsub(/([[]{2}|[]]{2})/, "", arrTOC[s])

          if(empty(summary))
            summary = "{{[[Template:" G["template"] "|" G["template"] "]]}} to [[" urlencodeawk(apiwikiname) "#" urlencodeawk(arrTOC[s]) "|#" arrTOC[s] "]]"
          else
            summary = summary " and [[" urlencodeawk(apiwikiname) "#" urlencodeawk(arrTOC[s]) "|#" arrTOC[s] "]]"
        }
      }
    }
  }

  if(summary || remcnt) {

    if(empty(summary)) {   # removed empty refs but added no template
      summary = "Remove " remcnt " empty ref tag" (remcnt > 1 ? "s" : "") " (via [[" G["botpage"] "|" BotName "]] bot)"
    }
    else {
      if(length(summary) > 400) {  # Exceeds limit see Help:Edit_summary#The_500-character_limit
        if(edcnt > 1)
          summary = "Add " edcnt " {{[[Template:" G["template"] "|" G["template"] "]]}}"
        else
          summary = "Add 1 {{[[Template:" G["template"] "|" G["template"] "]]}}"
      }
      else {
        if(edcnt > 1)
          summary = "Add " edcnt " " summary
        else
          summary = "Add " summary
      }

      if(remcnt)
        summary = summary ", remove " remcnt " empty ref tag" (remcnt > 1 ? "s" : "")

      summary = summary " (via [[" G["botpage"] "|" BotName "]] bot)"
    }

    upload(wikisource, apiwikiname, summary, G["log"], BotName, G["hostname"])

  }
}

#
# Load ~static/templates into G["templates"] - if a template is found, assume it has a ref
#  To create the templates file see 0README in ~static
#
function loadtemplates(  i,a,n,respace) {

  if(!checkexists(G["static"] "templates")) {
    stdErr(BotName ": missing template list: " G["static"] "templates")
    exit 1
  }

  for(i = 1; i <= splitn(G["static"] "templates", a, i); i++) {
    G["templates"] = G["templates"] "|" regesc3(a[i]) "|" regesc3("template:" a[i])
    n++
  }

  # An empty list leaves an alternation with an empty branch, which matches at every
  # position and turns the gsub() in reftalk() into a crawl rather than an error
  if(n == 0) {
    stdErr(BotName ": empty template list: " G["static"] "templates")
    exit 1
  }

  gsub(/^[|]|[|]$/, "", G["templates"])
  G["templates"] = "([{][{][ \\n]*[ ]*(" G["templates"] "))|([<][ ]*references)"

}

#
# Convert a date-eight (20120101) to Unix timestamp (UTC)
#
function d82unix(s) {
  return strftime("%s", mktime(substr(s, 1, 4) " " substr(s, 5, 2) " " substr(s, 7, 2) " 0 0 0"), 1)
}

#
# apititle() - the page reftalk actually operates on
#
#  A mainspace article is checked via its Talk: page; a title that is already a talk
#  page (G["re1"]) is used as-is.
#
function apititle(wikiname) {

  if (wikiname !~ G["re1"])
    return "Talk:" wikiname

  return wikiname
}

#
# getrendered() - rendered HTML for a page, as the raw action=parse JSON response
#
#  Replaces scraping https://en.wikipedia.org/wiki/<title>, which broke when enwiki
#  switched page views to Parsoid: the old markup <ol class="references"> no longer
#  appears there, so every page counted zero reference lists and reftalk() aborted
#  early on all of them. Asking action=parse for parsoid=1 gets the same rendering
#  readers see, through wikiget's OAuth and Toolforge proxy.
#
#  It also removes a failure mode: a missing page is a 404 on /wiki/, which http2var()
#  cannot distinguish from a network failure and retries for ~31 minutes. The Action
#  API answers a missing page with HTTP 200 and an error body.
#
function getrendered(wikiname) {

  return apiget(G["apiurl"] "action=parse&page=" urlencodeawk(apititle(wikiname)) "&prop=text&format=json&formatversion=2&parsoid=1&maxlag=" G["maxlag"])
}

#
# apiget() - send an API request and return the raw response
#
#  Routes through wikiget -U: OAuth credentials and the Toolforge proxy, instead of
#  wget against the public Varnish tier. wikiget absorbs maxlag and retries internally,
#  so keep the retry count here low - it is a second line of defense, not the first.
#
#  Returns "" if every attempt failed. Callers must handle that; note the Action API
#  answers a missing page with HTTP 200 and "missing":true, so "" means a real failure.
#
function apiget(url, tries,   i, res) {

  if (empty(tries))
    tries = G["apitries"]

  for (i = 1; i <= tries; i++) {
    res = sys2var(Exe["wikiget"] " -l " G["hostname"] " -U " shquote(url))
    if (!empty(res))
      return res
    if (i < tries)
      sleep(5, "unix")
  }

  return ""
}

#
# jsonunesc() - decode a JSON string body
#
#  Escaped quotes are real in this data: one 5000-row response starting at "\"" held
#  475 of them, in titles like "\"&\"". \uXXXX and \\ were not observed with
#  formatversion=2 (non-ASCII comes back as literal UTF-8) but are decoded anyway
#  rather than trusted not to appear.
#
#  Single left-to-right pass: a naive sequence of gsub() calls mis-handles runs like
#  \\" where the backslash is itself escaped. Guarded by a fast path, since the large
#  majority of titles contain no backslash at all.
#
function jsonunesc(s,   out, i, c, n) {

        if (index(s, "\\") == 0)
          return s

        n = length(s)
        for (i = 1; i <= n; i++) {
          c = substr(s, i, 1)
          if (c == "\\" && i < n) {
            i++
            c = substr(s, i, 1)
            if (c == "n") c = "\n"
            else if (c == "t") c = "\t"
            else if (c == "r") c = "\r"
            else if (c == "b") c = "\b"
            else if (c == "f") c = "\f"
            else if (c == "u") {
              c = jsonu8(substr(s, i + 1, 4))
              i += 4
            }
            # \" \\ \/ and anything else stand for themselves
          }
          out = out c
        }

        return out
}

#
# jsonu8() - one \uXXXX escape (4 hex digits) to UTF-8
#
#  Surrogate pairs are not joined: a non-BMP character arrives as two escapes and each
#  half converts on its own. Not reachable with formatversion=2, which sends literal
#  UTF-8 - this exists so an unexpected escape degrades instead of corrupting silently.
#
function jsonu8(hex,   cp) {

        cp = strtonum("0x" hex)
        if (cp < 0x80)
          return sprintf("%c", cp)
        if (cp < 0x800)
          return sprintf("%c%c", 0xC0 + int(cp / 64), 0x80 + (cp % 64))

        return sprintf("%c%c%c", 0xE0 + int(cp / 4096), 0x80 + int((cp % 4096) / 64), 0x80 + (cp % 64))
}

#
# batchstamps() - last-revision timestamps for a range of articles
#
#  Fills stamp[] keyed by talk title: a unix timestamp at day resolution, or 0 when the
#  talk page does not exist.
#
#  A title absent from stamp[] means the request failed. The caller must treat that as
#  "skip", never as "no talk page": a skipped article is never revisited, since the
#  block is already marked done in all-pages.done.
#
function batchstamps(article, first, last, stamp,   i, j, n, q, jsonin, jsona, id, t, ts, k) {

  delete stamp

  for (i = first; i <= last; i += G["apibatch"]) {

    q = ""
    n = 0
    for (j = i; j < i + G["apibatch"] && j <= last; j++) {
      if (empty(article[j])) continue
      q = q (empty(q) ? "" : "|") urlencodeawk(apititle(article[j]), "rawphp")
      n++
    }
    if (n == 0) continue

    jsonin = apiget(G["apiurl"] "action=query&prop=revisions&titles=" q "&rvprop=timestamp&format=json&formatversion=2&maxlag=" G["maxlag"])
    if (empty(jsonin)) continue

    delete jsona
    if (query_json(jsonin, jsona) < 0) continue

    for (k = 1; ; k++) {
      id = "query" SUBSEP "pages" SUBSEP k
      if (! ((id SUBSEP "title") in jsona)) break
      t = jsona[id SUBSEP "title"]
      ts = jsona[id SUBSEP "revisions" SUBSEP 1 SUBSEP "timestamp"]
      if (empty(ts))
        stamp[t] = 0
      else
        stamp[t] = d82unix(gsubi("[-]", "", substr(ts, 1, 10)))
    }
  }
}

#
# batchcontent() - talk page wikitext for the articles that passed the timestamp filter
#
function batchcontent(article, first, last, stamp, content,   i, j, n, q, jsonin, nc, parts, k, t, rest, raw, ls, want, nw) {

  delete content

  nw = 0
  for (j = first; j <= last; j++) {
    if (empty(article[j])) continue
    t = apititle(article[j])
    ls = stamp[t]
    if (empty(ls) || ls == 0) continue
    if (int(ls) < int(G["laststamp"])) continue
    want[++nw] = t
  }

  for (i = 1; i <= nw; i += G["apibatch"]) {

    q = ""
    n = 0
    for (j = i; j < i + G["apibatch"] && j <= nw; j++) {
      q = q (empty(q) ? "" : "|") urlencodeawk(want[j], "rawphp")
      n++
    }
    if (n == 0) continue

    jsonin = apiget(G["apiurl"] "action=query&prop=revisions&rvprop=content&rvslots=main&titles=" q "&format=json&formatversion=2&maxlag=" G["maxlag"])
    if (empty(jsonin)) continue

    # split() on the title key bounds each element to one page: a literal "title":" in
    # wikitext arrives escaped as \"title\":\" and cannot be mistaken for structure
    nc = split(jsonin, parts, /"title":"/)

    for (k = 2; k <= nc; k++) {

      if (! match(parts[k], /^(\\.|[^"\\])*"/)) continue
      t = jsonunesc(substr(parts[k], 1, RLENGTH - 1))
      rest = substr(parts[k], RLENGTH + 1)

      # "contentmodel" and "contentformat" precede it but do not match "content":"
      if (! match(rest, /"content":"(\\.|[^"\\])*"/)) {
        content[t] = ""
        continue
      }

      raw = substr(rest, RSTART + 11, RLENGTH - 12)
      if (index(raw, "<ref") == 0)
        content[t] = ""
      else
        content[t] = jsonunesc(raw)
    }
  }
}

