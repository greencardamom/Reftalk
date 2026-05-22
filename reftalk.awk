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
  G["re1"]    = "^(Wikipedia talk[:]|User talk[:])"

  # Timestamp when the program last ran. Generate via:
  #  awk -ilibrary 'BEGIN{s = "20210201"; print strftime("%s", mktime(substr(s, 1, 4) " " substr(s, 5, 2) " " substr(s, 7, 2) " 0 0 0"), 1)}'

  # 2024-03-01  (timestamp of the old all-pages file)
  G["laststamp"] = "1740823200"

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

function main(  i,a,j,bz,sz,ez,sp,z,command,dn,bm,la,startpoint,offset,endall,bl,article,al,artblock) {

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
            if(wikiname !~ G["re1"]) 
              reftalk(http2var("https://en.wikipedia.org/wiki/Talk:" urlencodeawk(a[i])), a[i])
            else 
              reftalk(http2var("https://en.wikipedia.org/wiki/" urlencodeawk(a[i])), a[i])
          }
        }
      }

      else {  # single page mode

        CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

        if(sp !~ G["re1"]) 
          reftalk(http2var("https://en.wikipedia.org/wiki/Talk:" urlencodeawk(sp)), sp)
        else 
          reftalk(http2var("https://en.wikipedia.org/wiki/" urlencodeawk(sp)), sp)
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
        offset = wc(G["log"] "all-pages.offset") 
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

        # Iterate through the 1..1000 individual articles in artblock
        for(al = offset; al <= splitn(artblock "\n", article, al, offset); al++) {
         
          # Log to offset file
          print al >> G["log"] "all-pages.offset"
          close(G["log"] "all-pages.offset")

          # Log debug file (optional)
          # print bl "-" bl+999 " " al >> G["log"] "all-pages.debug"
          # close(G["log"] "all-pages.debug")

          # Skip if page has not been edited since last time bot ran 
          ls = laststamp("Talk:" article[al])
          if(!empty(ls) && ls != 0) {
            if( int(ls) < int(G["laststamp"])) {
              #print "Warning: laststamp (" ls ") exceeded (" article[al] ") ---- " CurTime >> G["log"] "syslog"
              #close(G["log"] "syslog")
              continue
            }
            else {
              #print "Info: laststamp (" ls ") in range (" article[al] ") ---- " CurTime >> G["log"] "syslog"
              #close(G["log"] "syslog")
            }
          }
          else { # No talk page probably, see laststamp() for logged error messages
            continue
          }

          # Run bot on given article title
          if(wikiname !~ G["re1"])
            reftalk(http2var("https://en.wikipedia.org/wiki/Talk:" urlencodeawk(article[al])), article[al])
          else
            reftalk(http2var("https://en.wikipedia.org/wiki/" urlencodeawk(article[al])), article[al])
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
function reftalk(wikihtml, wikiname,   tfp,i,j,k,l,fp) {

  tfp = stripwikicomments(wikihtml)
  j = gsub(/<[ ]*ol[ ]*class[ ]*[=][ ]*"references"[ ]*[>]/, "", tfp)
  if(j == 0)           # abort early - no refs on page
    return 0

  if(wikiname !~ G["re1"]) 
    fp = sys2var(Exe["wikiget"] " -w " shquote("Talk:" wikiname) )
  else 
    fp = sys2var(Exe["wikiget"] " -w " shquote(wikiname) )

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
function addreftalk(wikisource, wikiname,    jsoninTOC,jsonaTOC,arrTOC,jsoninSecW,jsonaSecW,arrSecW,s,a,mid,i,out,summary,edcnt,origWS,origSec,apiname,b) {

  if(wikiname !~ G["re1"]) 
    apiwikiname = "Talk:" wikiname
  else 
    apiwikiname = wikiname

  # Get index of sections, then step through each one looking for a missing {{relist}} in the content

  jsoninTOC = http2var("https://en.wikipedia.org/w/api.php?action=parse&page=" urlencodeawk(apiwikiname) "&prop=sections&format=json&formatversion=2&maxlag=5")

  if( query_json(jsoninTOC, jsonaTOC) >= 0) {

    # awkenough_dump(jsonaTOC, "jsonaTOC")
    # jsona["parse","sections","2","line"]=Please do not "correct" the statement about universal donors

    splitja(jsonaTOC, arrTOC, 3, "line")

    for(s in arrTOC) {

      if(jsonaTOC["parse","sections",s,"toclevel"] != 1) continue # skip if not a 1st level section ie. == <section> == 

      jsoninSecW = http2var("https://en.wikipedia.org/w/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&rvlimit=1&titles=" urlencodeawk(apiwikiname) "&rvsection=" s "&format=json&formatversion=2&maxlag=5")

      if( query_json(jsoninSecW, jsonaSecW) >= 0) {

        # awkenough_dump(jsonaSecW, "jsonaSecW")
        # jsona2["query","pages","1","revisions","1","slots","main","content"]=

        splitja(jsonaSecW, arrSecW, 5, "content")

        # print "title   = " arrTOC[s]
        # print "content = " arrSecW["1"]

        if(match(stripnowikicom(arrSecW["1"]), /[<][ ]*ref[ ]*/) && match(stripnowikicom(arrSecW["1"]), /[<][ ]*\/[ ]*ref[ ]*[>]/) && ! match(stripnowikicom(arrSecW["1"]), G["templates"]) ) {

          CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

          # Check for empty <ref></ref>
          origSec = arrSecW["1"]
          gsub(/[<]ref[>][ ]*[<][ ]*\/[ ]*ref[>]/, "", origSec)
          if(!match(stripnowikicom(origSec), /[<][ ]*ref[ ]*/)) {
            print wikiname " ---- " CurTime " ---- empty <ref></ref> in section \"" arrTOC[s] "\"" >> G["log"] "error"
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

          # Add the template, check and log if error
          out = arrSecW["1"] mid "\n{{reflist-talk}}" 
          origWS = wikisource
          wikisource = gsubs(arrSecW["1"], out, wikisource)
          if(origWS == wikisource) {
            print wikiname " ---- " CurTime " ---- gsubs() failure" >> G["log"] "error"
            continue
          }
          edcnt++

          # mis-match caused by transclusions
          if( ! match(arrSecW["1"], "[=]{1,2}[ ]*" regesc3(arrTOC[s]))) { 
            arrTOC[s] = strip(a[1])
            gsub(/^[=]{1,2}[ ]*|[ ]*[=]{1,2}$/, "", arrTOC[s])
          }

          # remove any "[[" and "]]" in title#sectionname otherwise it renders incorrectly
          gsub(/([[]{2}|[]]{2})/, "", arrTOC[s])

          if(empty(summary))
            summary = "{{[[Template:reflist-talk|reflist-talk]]}} to [[" urlencodeawk(apiwikiname) "#" urlencodeawk(arrTOC[s]) "|#" arrTOC[s] "]]"
          else
            summary = summary " and [[" urlencodeawk(apiwikiname) "#" urlencodeawk(arrTOC[s]) "|#" arrTOC[s] "]]"
        }
      }
    }
  }

  if(summary) {

    if(length(summary) > 400) {  # Exceeds limit see Help:Edit_summary#The_500-character_limit
      if(edcnt > 1)
        summary = "Add " edcnt " {{[[Template:reflist-talk|reflist-talk]]}} (via [[User:GreenC bot/Job 8|reftalk]] bot)"
      else
        summary = "Add 1 {{[[Template:reflist-talk|reflist-talk]]}} (via [[User:GreenC bot/Job 8|reftalk]] bot)"      
    }
    else {
      if(edcnt > 1)
        summary = "Add " edcnt " " summary " (via [[User:GreenC bot/Job 8|reftalk]] bot)"
      else
        summary = "Add " summary " (via [[User:GreenC bot/Job 8|reftalk]] bot)"      
    }

    upload(wikisource, apiwikiname, summary, G["log"], BotName, "en")

  }
}

#
# Load ~static/templates into G["templates"] - if a template is found, assume it has a ref
#  To create the templates file see 0README in ~static
#
function loadtemplates(  i,a,respace) {

  for(i = 1; i <= splitn(G["static"] "templates", a, i); i++)
    G["templates"] = G["templates"] "|" regesc3(a[i]) "|" regesc3("template:" a[i])   
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
# Return last revision timestamp (unix time UTC) for given article
#  Has 4 seconds and 1 try to get it, otherwise return "" 
#  No error-checking, fast as possible
#
function laststamp(article,  jsonin,url,d,a,command,ts) {

  url = "https://en.wikipedia.org/w/api.php?action=query&prop=revisions&titles=" urlencodeawk(article) "&rvslots=*&rvprop=timestamp&format=json"

  if (url ~ /'/)
       gsub(/'/, "%27", url)
  if (url ~ /’/)
       gsub(/’/, "%E2%80%99", url)

  command = Exe["timeout"] " 4s " Exe["wget"] Wget_opts " -q -O- " shquote(url)
  jsonin = sys2var(command)

  CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

  # "timestamp":"2019-09-11T16:02:20Z"
  if(match(jsonin, /"timestamp":"[^"]+["]/, d)) {
    split(d[0], a, /"/)
    ts = d82unix(gsubi("[-]", "", substr(a[4],1,10)))
    if(length(ts) > 9 && isanumber(ts))
      return int(ts)
    else {
      print "Warning laststamp: unable to convert timestamp (" article ") for (" a[4] ") into (" ts ") ---- " CurTime >> G["log"] "syslog"
      close(G["log"] "syslog")
      return ""
    }
  }

  if(match(jsonin, /"missing":/)) {
    print "Warning laststamp: missing talk page (" article ") ---- " CurTime >> G["log"] "syslog"
    close(G["log"] "syslog")
    return ""
  }

  print "Warning laststamp: timeout revisions API (" article ") for (" command ") ---- " CurTime >> G["log"] "syslog"
  close(G["log"] "syslog")
  return "" 

}

