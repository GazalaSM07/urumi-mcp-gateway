import os,base64,hmac,hashlib,secrets
from datetime import datetime,timezone
import httpx
from fastapi import FastAPI,Request
from urllib.parse import quote

app=FastAPI()
STORE_URL=os.getenv('WC_URL','http://wordpress').rstrip('/')
SIGNING_STORE_URL=os.getenv('WC_SIGNING_URL',STORE_URL).rstrip('/')
URL=STORE_URL+'/wp-json/wc/v3'
KEY=os.getenv('WC_CONSUMER_KEY',''); SECRET=os.getenv('WC_CONSUMER_SECRET','')
def safe_error(exc):
    if isinstance(exc,httpx.HTTPStatusError):
        response=exc.response
        try:
            body=response.json()
            code=body.get('code') if isinstance(body,dict) else None
            message=body.get('message') if isinstance(body,dict) else None
            if code or message:
                detail=f' ({code})' if code else ''
                if message:
                    message=str(message)
                    for credential in (KEY,SECRET):
                        if credential: message=message.replace(credential,'[redacted]')
                    detail+=f': {message[:200]}'
                return f'WooCommerce API returned HTTP {response.status_code}{detail}'
        except Exception:
            pass
        return f'WooCommerce API returned HTTP {response.status_code} {response.reason_phrase}'.strip()
    if isinstance(exc,httpx.RequestError):
        return 'Could not connect to the WooCommerce API'
    message=str(exc)
    for credential in (KEY,SECRET):
        if credential: message=message.replace(credential,'[redacted]')
    return message[:300]
async def wc(method,path,**kwargs):
    if not KEY or not SECRET: raise RuntimeError('WooCommerce REST credentials are not configured')
    params=dict(kwargs.pop('params',{}) or {})
    auth=None
    if URL.startswith('https://'):
        auth=(KEY,SECRET)
    else:
        oauth={'oauth_consumer_key':KEY,'oauth_nonce':secrets.token_hex(16),'oauth_signature_method':'HMAC-SHA1','oauth_timestamp':str(int(datetime.now(timezone.utc).timestamp())),'oauth_version':'1.0'}
        all_params={**params,**oauth}
        encode=lambda value:quote(str(value),safe='~-._')
        normalized='&'.join(f'{k}={v}' for k,v in sorted((encode(k),encode(v)) for k,v in all_params.items()))
        # WooCommerce validates OAuth against its canonical home URL, which is
        # the Ingress hostname, even though this adapter connects to the
        # in-cluster WordPress Service.
        base_url=SIGNING_STORE_URL+'/wp-json/wc/v3'+path
        base='&'.join((method.upper(),encode(base_url),encode(normalized)))
        signature=base64.b64encode(hmac.new((encode(SECRET)+'&').encode(),base.encode(),hashlib.sha1).digest()).decode()
        params={**params,**oauth,'oauth_signature':signature}
    async with httpx.AsyncClient(timeout=12) as c:
        r=await c.request(method,URL+path,params=params,auth=auth,**kwargs); r.raise_for_status(); return r.json() if r.content else {}
TOOLS=[
 {'name':'list_products','description':'List WooCommerce products. Supports search, page and per_page.','inputSchema':{'type':'object','properties':{'search':{'type':'string'},'page':{'type':'integer','default':1},'per_page':{'type':'integer','default':20}},'additionalProperties':False}},
 {'name':'create_product','description':'Create a published simple product with a name, price, and optional description.','inputSchema':{'type':'object','properties':{'name':{'type':'string'},'price':{'type':'string'},'description':{'type':'string'}},'required':['name','price'],'additionalProperties':False}},
 {'name':'list_orders','description':'List orders, newest first. Use after and before ISO timestamps to filter a date window.','inputSchema':{'type':'object','properties':{'after':{'type':'string'},'before':{'type':'string'},'page':{'type':'integer','default':1},'per_page':{'type':'integer','default':20}},'additionalProperties':False}},
 {'name':'get_order','description':'Get one WooCommerce order by numeric ID.','inputSchema':{'type':'object','properties':{'order_id':{'type':'integer'}},'required':['order_id'],'additionalProperties':False}},
 {'name':'update_order_status','description':'Change an order status.','inputSchema':{'type':'object','properties':{'order_id':{'type':'integer'},'status':{'type':'string','enum':['pending','processing','on-hold','completed','cancelled','refunded','failed']}},'required':['order_id','status'],'additionalProperties':False}}
]
async def call(name,a):
 if name=='list_products': return await wc('GET','/products',params={k:v for k,v in {'search':a.get('search'),'page':a.get('page',1),'per_page':min(a.get('per_page',20),100)}.items() if v is not None})
 if name=='create_product': return await wc('POST','/products',json={'name':a['name'],'type':'simple','regular_price':str(a['price']),'description':a.get('description',''),'status':'publish'})
 if name=='list_orders':
  params={'page':a.get('page',1),'per_page':min(a.get('per_page',20),100),'orderby':'date','order':'desc'}
  if a.get('after'): params['after']=a['after']
  if a.get('before'): params['before']=a['before']
  return await wc('GET','/orders',params=params)
 if name=='get_order': return await wc('GET',f"/orders/{int(a['order_id'])}")
 if name=='update_order_status': return await wc('PUT',f"/orders/{int(a['order_id'])}",json={'status':a['status']})
 raise ValueError('Unknown tool')
@app.get('/healthz')
def health(): return {'ok':True}
@app.post('/mcp')
async def mcp(req:Request):
 p=await req.json(); method=p.get('method'); rid=p.get('id'); params=p.get('params') or {}
 try:
  if method=='initialize': result={'protocolVersion':params.get('protocolVersion','2025-03-26'),'capabilities':{'tools':{'listChanged':False}},'serverInfo':{'name':'woocommerce-mcp','version':'1.0.0'}}
  elif method=='ping': result={}
  elif method=='tools/list': result={'tools':TOOLS}
  elif method=='tools/call':
   try: result={'content':[{'type':'text','text':__import__('json').dumps(await call(params['name'],params.get('arguments') or {}))}]}
   except Exception as e: result={'isError':True,'content':[{'type':'text','text':safe_error(e)}]}
  else: return {'jsonrpc':'2.0','id':rid,'error':{'code':-32601,'message':'Method not found'}}
  return {'jsonrpc':'2.0','id':rid,'result':result}
 except Exception as e: return {'jsonrpc':'2.0','id':rid,'error':{'code':-32000,'message':safe_error(e)}}
