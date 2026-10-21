import json,sys,urllib.request,re
port=sys.argv[1]; q=sys.argv[2]
key=re.search(r'"apiKey": *"([^"]*)',urllib.request.urlopen(f"http://127.0.0.1:{port}/initialize.json").read().decode()).group(1)
req=urllib.request.Request(f"http://127.0.0.1:{port}/api/v3/release?{q}",headers={"X-Api-Key":key})
rs=json.loads(urllib.request.urlopen(req,timeout=170).read())
rs.sort(key=lambda r:(-r.get("customFormatScore",0),-r.get("seeders",0)))
print(len(rs),"releases")
for r in rs[:int(sys.argv[3]) if len(sys.argv)>3 else 14]:
    cfs=[c["name"] for c in r.get("customFormats",[])]
    rej=r.get("rejections",[])
    print(f'{r["customFormatScore"]:>7} ok={str(r["approved"])[0]} {r["indexer"].replace(" (Prowlarr)","")[:9]:9} {r["quality"]["quality"]["name"]:13} s={r["seeders"]:<5} {cfs} | {r["title"][:60]} {("REJ:"+rej[0][:40]) if rej else ""}')
