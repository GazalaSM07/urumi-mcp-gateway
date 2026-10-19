import os,json
from fastapi import FastAPI,Request
app=FastAPI(); KIND=os.getenv('KIND','inventory')
TOOLS={
 'inventory':[{'name':'search_inventory_notes','description':'Search the team inventory notes for product availability context.','inputSchema':{'type':'object','properties':{'query':{'type':'string'}},'required':['query']}},{'name':'get_restock_eta','description':'Get a sample restock estimate for a product.','inputSchema':{'type':'object','properties':{'product':{'type':'string'}},'required':['product']}}],
 'metrics':[{'name':'get_store_metrics','description':'Return sample store metrics for a period.','inputSchema':{'type':'object','properties':{'period':{'type':'string','description':'today, week, or month'}},'required':['period']}},{'name':'get_daily_revenue','description':'Return sample revenue for a date (YYYY-MM-DD).','inputSchema':{'type':'object','properties':{'date':{'type':'string'}},'required':['date']}}]}
def run(name,args):
 if name=='search_inventory_notes': return {'query':args['query'],'notes':['Demo catalog: sample products are tracked by WooCommerce; this server provides supplemental team notes.']}
 if name=='get_restock_eta': return {'product':args['product'],'estimated_days':5,'source':'demo inventory'}
 if name=='get_store_metrics': return {'period':args['period'],'sessions':1280,'orders':42,'conversion_rate':0.0328,'source':'demo metrics'}
 if name=='get_daily_revenue': return {'date':args['date'],'revenue':1842.50,'currency':'USD','source':'demo metrics'}
 raise ValueError('Unknown tool')
@app.get('/healthz')
def health(): return {'ok':True,'kind':KIND}
@app.post('/mcp')
async def mcp(req:Request):
 p=await req.json(); m=p.get('method'); rid=p.get('id'); a=p.get('params') or {}
 if m=='initialize': r={'protocolVersion':a.get('protocolVersion','2025-03-26'),'capabilities':{'tools':{'listChanged':False}},'serverInfo':{'name':KIND+'-demo-mcp','version':'1.0.0'}}
 elif m=='ping': r={}
 elif m=='tools/list': r={'tools':TOOLS[KIND]}
 elif m=='tools/call':
  try:r={'content':[{'type':'text','text':json.dumps(run(a['name'],a.get('arguments') or {}))}]}
  except Exception as e:r={'isError':True,'content':[{'type':'text','text':str(e)}]}
 else:return {'jsonrpc':'2.0','id':rid,'error':{'code':-32601,'message':'Method not found'}}
 return {'jsonrpc':'2.0','id':rid,'result':r}
