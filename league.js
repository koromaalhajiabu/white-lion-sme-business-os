/* White Lion — Sports & Local League Management module */
(() => {
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let competitionId = '', seasonId = '', activeTab = 'overview', cache = {};
  const host = () => document.getElementById('view');
  const cloud = () => window.whiteLionCloud;
  const client = () => cloud()?.getClient?.();
  const business = () => cloud()?.getActiveBusiness?.();
  const moneylessDate = v => v ? new Date(v).toLocaleString() : 'Not scheduled';
  const notice = msg => { const el=document.getElementById('wlLeagueNotice'); if(el){el.textContent=msg;el.hidden=false;} };
  const hideNotice = () => { const el=document.getElementById('wlLeagueNotice'); if(el)el.hidden=true; };
  const tabs = [
    ['overview','Overview'],['clubs','Clubs'],['players','Players'],['fixtures','Fixtures & Results'],
    ['table','League Table'],['stats','Player Statistics'],['discipline','Discipline'],['access','Access & Roles']
  ];
  const currentCompetition = () => (cache.competitions||[]).find(x=>x.id===competitionId);
  const currentSeason = () => (cache.seasons||[]).find(x=>x.id===seasonId);
  const selectOptions = (items, valueKey='id', labelKey='name', placeholder='Select…') =>
    '<option value="">'+esc(placeholder)+'</option>' + items.map(x=>'<option value="'+esc(x[valueKey])+'">'+esc(x[labelKey])+'</option>').join('');
  const field = (label,name,type='text',required=false,extra='') =>
    '<label class="wl-league-field"><span>'+esc(label)+'</span><input name="'+esc(name)+'" type="'+type+'" '+(required?'required':'')+' '+extra+'></label>';
  const selectField = (label,name,options,required=true) =>
    '<label class="wl-league-field"><span>'+esc(label)+'</span><select name="'+esc(name)+'" '+(required?'required':'')+'>'+options+'</select></label>';
  const button = (label,kind='primary',extra='') => '<button class="wl-league-btn '+kind+'" '+extra+'>'+esc(label)+'</button>';
  const empty = text => '<div class="wl-league-empty">'+esc(text)+'</div>';
  const table = (heads, rows) => '<div class="wl-league-table-wrap"><table><thead><tr>'+heads.map(h=>'<th>'+h+'</th>').join('')+'</tr></thead><tbody>'+(rows||'<tr><td colspan="'+heads.length+'">'+empty('No records yet.')+'</td></tr>')+'</tbody></table></div>';
  function styles(){
    if(document.getElementById('wlLeagueStyles'))return;
    const s=document.createElement('style');s.id='wlLeagueStyles';s.textContent=`
      .wl-league{color:#173126}.wl-league-hero{display:flex;justify-content:space-between;align-items:flex-start;gap:15px;padding:20px;margin-bottom:15px;border:1px solid #d9e9de;border-radius:17px;background:linear-gradient(120deg,#eff9f1,#fff 65%,#eef6fc)}
      .wl-league-hero h1{margin:4px 0 5px;font-size:clamp(21px,2.3vw,28px);color:#075b35;letter-spacing:-.6px}.wl-league-hero p{margin:0;color:#718078;font-size:12px;line-height:1.6}.wl-league-kicker{font-size:10px;font-weight:850;letter-spacing:1.5px;color:#087a43;text-transform:uppercase}
      .wl-league-mark{width:48px;height:48px;flex:0 0 48px;border-radius:14px;display:grid;place-items:center;color:#fff;font-weight:900;background:linear-gradient(145deg,#1eb53a 0 36%,#fff 36% 67%,#0072c6 67%);border:1px solid #d9e9de}
      .wl-league-toolbar{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin:0 0 14px}.wl-league-toolbar select{flex:1;min-width:190px}
      .wl-league-btn{border:1px solid #d9e7de;border-radius:9px;padding:9px 12px;background:#fff;color:#244534;font-size:11px;font-weight:800;min-height:39px}.wl-league-btn.primary{background:#087a43;border-color:#087a43;color:#fff}.wl-league-btn.blue{background:#0072c6;border-color:#0072c6;color:#fff}.wl-league-btn:disabled{opacity:.55}
      .wl-league-tabs{display:flex;gap:6px;overflow:auto;padding:3px 2px 11px;margin-bottom:5px}.wl-league-tab{white-space:nowrap;border:1px solid #e0e9e3;background:#fff;color:#62766a;border-radius:30px;padding:9px 13px;font-size:10px;font-weight:800}.wl-league-tab.active{background:#087a43;border-color:#087a43;color:#fff}
      .wl-league-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-bottom:14px}.wl-league-card{background:#fff;border:1px solid #e0eae3;border-radius:14px;padding:15px;box-shadow:0 6px 20px rgba(7,91,53,.045);min-width:0}.wl-league-card small{display:block;color:#718078;font-size:10px}.wl-league-card strong{display:block;color:#075b35;font-size:24px;margin:5px 0 2px}.wl-league-panel{background:#fff;border:1px solid #e0eae3;border-radius:14px;padding:16px;margin-bottom:13px;min-width:0}.wl-league-panel h3{margin:0 0 5px;color:#17432b;font-size:14px}.wl-league-sub{font-size:10px;color:#7b8b81;line-height:1.55;margin-bottom:12px}
      .wl-league-form{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.wl-league-field{display:grid;gap:5px;min-width:0}.wl-league-field.full{grid-column:1/-1}.wl-league-field span{font-size:10px;color:#526b5b;font-weight:800}.wl-league-field input,.wl-league-field select,.wl-league-field textarea{width:100%;min-width:0;min-height:39px;padding:9px 10px;border:1px solid #dce8df;border-radius:9px;background:#fff;color:#203b2b;font:inherit;font-size:11px}.wl-league-field textarea{min-height:70px;resize:vertical}.wl-league-actions{display:flex;gap:7px;flex-wrap:wrap;align-items:center;margin-top:11px}
      .wl-league-table-wrap{width:100%;overflow:auto;border:1px solid #e8eee9;border-radius:10px;-webkit-overflow-scrolling:touch}.wl-league-table-wrap table{width:100%;border-collapse:collapse;white-space:nowrap}.wl-league-table-wrap th{background:#f3f8f4;color:#61776a;font-size:9px;padding:10px;text-align:left}.wl-league-table-wrap td{padding:10px;border-top:1px solid #edf2ee;color:#31483a;font-size:10px}.wl-league-empty{padding:22px 12px;text-align:center;color:#829087;font-size:11px}
      .wl-league-notice{padding:11px 13px;border:1px solid #cfe5d5;border-radius:10px;background:#f1faf3;color:#23633c;font-size:11px;margin-bottom:12px}.wl-league-notice[hidden]{display:none}.wl-league-muted{color:#839087;font-size:10px;line-height:1.6}.wl-league-inline{display:flex;gap:7px;align-items:center;flex-wrap:wrap}.wl-league-inline input{width:70px;min-height:33px;padding:5px;border:1px solid #dce8df;border-radius:7px}.wl-league-badge{display:inline-block;padding:4px 7px;border-radius:20px;background:#eaf6ed;color:#087a43;font-size:9px;font-weight:800}.wl-league-badge.warn{background:#fff4df;color:#986b1c}
      @media(max-width:900px){.wl-league-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:600px){.wl-league-hero{padding:15px}.wl-league-mark{width:39px;height:39px;flex-basis:39px}.wl-league-grid{gap:8px}.wl-league-card{padding:12px}.wl-league-card strong{font-size:21px}.wl-league-panel{padding:13px}.wl-league-form{grid-template-columns:1fr}.wl-league-field.full{grid-column:auto}.wl-league-toolbar select{width:100%;min-width:0}.wl-league-actions .wl-league-btn{flex:1}}
    `;document.head.appendChild(s);
  }
  async function load(){
    const c=client(),b=business();
    if(!c||!b?.id)throw new Error('Sign in and select a business workspace to manage its competitions.');
    const {data:competitions,error}=await c.from('league_competitions').select('*').eq('business_id',b.id).order('created_at',{ascending:false});
    if(error)throw error;
    cache.competitions=competitions||[];
    if(!competitionId||!cache.competitions.some(x=>x.id===competitionId))competitionId=cache.competitions[0]?.id||'';
    if(!competitionId){cache.seasons=[];cache.clubs=[];cache.players=[];cache.fixtures=[];return}
    const [seasons,clubs,players,fixtures]=await Promise.all([
      c.from('league_seasons').select('*').eq('business_id',b.id).eq('competition_id',competitionId).order('starts_on',{ascending:false}),
      c.from('league_clubs').select('*').eq('business_id',b.id).eq('competition_id',competitionId).order('name'),
      c.from('league_players').select('*').eq('business_id',b.id).eq('competition_id',competitionId).order('full_name'),
      c.from('league_fixtures').select('*').eq('business_id',b.id).eq('competition_id',competitionId).order('kickoff_at',{ascending:true})
    ]);
    for(const x of [seasons,clubs,players,fixtures])if(x.error)throw x.error;
    cache.seasons=seasons.data||[];cache.clubs=clubs.data||[];cache.players=players.data||[];cache.fixtures=fixtures.data||[];
    if(!seasonId||!cache.seasons.some(x=>x.id===seasonId))seasonId=cache.seasons.find(x=>x.status==='active')?.id||cache.seasons[0]?.id||'';
  }
  function base(title,sub,body){
    const c=currentCompetition();
    return '<div class="wl-league"><div class="wl-league-hero"><div><div class="wl-league-kicker">White Lion · Community & Sports</div><h1>'+esc(title)+'</h1><p>'+esc(sub)+'</p></div><div class="wl-league-mark">WL</div></div><div id="wlLeagueNotice" class="wl-league-notice" hidden></div>'+
      '<div class="wl-league-toolbar"><select id="wlLeagueCompetition">'+selectOptions(cache.competitions||[],'id','name','Choose a competition')+'</select>'+
      (c?'<select id="wlLeagueSeason">'+selectOptions(cache.seasons||[],'id','name','Choose a season')+'</select>':'')+
      button('＋ New competition','primary','id="wlLeagueNewCompetition"')+'</div>'+
      (c?'<div class="wl-league-tabs">'+tabs.map(([id,label])=>'<button class="wl-league-tab '+(activeTab===id?'active':'')+'" data-league-tab="'+id+'">'+label+'</button>').join('')+'</div>':'')+
      body+'</div>';
  }
  function overview(){
    const c=currentCompetition(),s=currentSeason(),clubs=cache.clubs||[],players=cache.players||[],fixtures=(cache.fixtures||[]).filter(x=>!seasonId||x.season_id===seasonId);
    const completed=fixtures.filter(x=>x.status==='completed').length,upcoming=fixtures.filter(x=>x.status==='scheduled').length;
    return '<div class="wl-league-grid"><div class="wl-league-card"><small>Registered clubs</small><strong>'+clubs.length+'</strong><small>In this competition</small></div><div class="wl-league-card"><small>Registered players</small><strong>'+players.length+'</strong><small>Across all clubs</small></div><div class="wl-league-card"><small>Fixtures completed</small><strong>'+completed+'</strong><small>'+upcoming+' scheduled fixtures</small></div></div>'+
      '<div class="wl-league-panel"><h3>'+esc(c.name)+' · '+esc(s?.name||'No season selected')+'</h3><div class="wl-league-sub">'+esc(c.competition_type)+' · '+esc(c.region||'Region not set')+' · '+esc(c.organiser||'Organiser not set')+'</div>'+
      (s?'Season dates: '+esc(s.starts_on||'TBC')+' to '+esc(s.ends_on||'TBC')+' · <span class="wl-league-badge">'+esc(s.status)+'</span>':'Create a season to start scheduling fixtures.')+
      '<div class="wl-league-actions">'+button('Add season','primary','data-league-action="new-season"')+button('Register club','', 'data-league-action="new-club"')+button('Create fixture','blue','data-league-action="new-fixture"')+'</div></div>'+
      '<div class="wl-league-panel"><h3>Competition workflow</h3><div class="wl-league-sub">Set up a competition, create its season, register participating clubs and squads, then publish fixtures and enter verified results. League positions and player statistics are calculated from completed match records.</div><div class="wl-league-muted">Data is separated by the active White Lion business. Access is controlled by Supabase roles and row-level security.</div></div>';
  }
  function clubsView(){
    const rows=(cache.clubs||[]).map(x=>'<tr><td><b>'+esc(x.name)+'</b><br><small>'+esc(x.short_name||'')+'</small></td><td>'+esc(x.home_venue||'—')+'</td><td>'+esc(x.manager_name||'—')+'</td><td><span class="wl-league-badge">'+esc(x.status)+'</span></td></tr>').join('');
    return '<div class="wl-league-panel"><h3>Club register</h3><div class="wl-league-sub">Add clubs, home grounds and club contacts to this competition.</div><form class="wl-league-form" data-league-form="club">'+field('Club name','name','text',true)+field('Short name / abbreviation','short_name')+field('Home venue','home_venue')+field('Club manager','manager_name')+field('Contact phone','contact_phone','tel')+field('Club crest URL (optional)','crest_url','url')+'<div class="wl-league-field full">'+button('Save club','primary')+'</div></form></div><div class="wl-league-panel"><h3>Registered clubs · '+(cache.clubs||[]).length+'</h3>'+table(['Club','Home venue','Manager','Status'],rows)+'</div>';
  }
  function playersView(){
    const rows=(cache.players||[]).map(p=>'<tr><td><b>'+esc(p.full_name)+'</b></td><td>'+esc((cache.clubs||[]).find(c=>c.id===p.club_id)?.name||'—')+'</td><td>'+esc(p.shirt_number??'—')+'</td><td>'+esc(p.position||'—')+'</td><td>'+esc(p.nationality||'—')+'</td><td>'+esc(p.status)+'</td></tr>').join('');
    return '<div class="wl-league-panel"><h3>Player registration</h3><div class="wl-league-sub">Register players under their club. Shirt numbers must be between 1 and 99.</div>'+
      (cache.clubs?.length?'<form class="wl-league-form" data-league-form="player">'+field('Player full name','full_name','text',true)+selectField('Club','club_id',selectOptions(cache.clubs))+
      field('Shirt number','shirt_number','number',false,'min="1" max="99"')+selectField('Position','position',['<option value="">Select position…</option>',...['Goalkeeper','Defender','Midfielder','Forward'].map(x=>'<option>'+x+'</option>')].join(''))+
      field('Date of birth','date_of_birth','date')+field('Nationality','nationality')+'<div class="wl-league-field full">'+button('Register player','primary')+'</div></form>':empty('Register a club before adding players.'))+'</div>'+
      '<div class="wl-league-panel"><h3>Player register · '+(cache.players||[]).length+'</h3>'+table(['Player','Club','No.','Position','Nationality','Status'],rows)+'</div>';
  }
  function fixturesView(){
    const rows=(cache.fixtures||[]).filter(f=>!seasonId||f.season_id===seasonId).map(f=>{
      const home=cache.clubs.find(c=>c.id===f.home_club_id)?.name||'Home',away=cache.clubs.find(c=>c.id===f.away_club_id)?.name||'Away';
      const score=f.status==='completed'?'<b>'+f.home_score+' - '+f.away_score+'</b>':'—';
      const resultForm=f.status==='completed'?'':('<form class="wl-league-inline" data-league-result="'+f.id+'"><input type="number" name="home_score" min="0" placeholder="H" required><b>:</b><input type="number" name="away_score" min="0" placeholder="A" required><button class="wl-league-btn primary">Save result</button></form>');
      return '<tr><td>'+esc(moneylessDate(f.kickoff_at))+'</td><td>'+esc(home)+'</td><td>'+esc(away)+'</td><td>'+score+'</td><td>'+esc(f.venue||'—')+'</td><td>'+esc(f.status)+'</td><td>'+resultForm+'</td></tr>';
    }).join('');
    return '<div class="wl-league-panel"><h3>Fixture scheduling</h3><div class="wl-league-sub">Create fixtures for the selected season. Enter a final score to complete a match and update the league table.</div>'+
      (cache.seasons?.length&&cache.clubs?.length>=2?'<form class="wl-league-form" data-league-form="fixture">'+selectField('Home club','home_club_id',selectOptions(cache.clubs))+
      selectField('Away club','away_club_id',selectOptions(cache.clubs))+field('Kick-off date and time','kickoff_at','datetime-local',true)+field('Venue','venue')+field('Matchweek / round','matchweek')+field('Referee','referee_name')+'<div class="wl-league-field full">'+button('Create fixture','primary')+'</div></form>':empty('Create a season and register at least two clubs before scheduling fixtures.'))+'</div>'+
      '<div class="wl-league-panel"><h3>Fixtures & results</h3>'+table(['Date','Home team','Away team','Score','Venue','Status','Enter result'],rows)+'</div>';
  }
  async function tableView(){
    if(!seasonId)return '<div class="wl-league-panel">'+empty('Create and select a season to view its table.')+'</div>';
    const {data,error}=await client().from('league_standings').select('*').eq('business_id',business().id).eq('competition_id',competitionId).eq('season_id',seasonId).order('points',{ascending:false}).order('goal_difference',{ascending:false}).order('goals_for',{ascending:false});
    if(error)throw error;
    const rows=(data||[]).map((r,i)=>'<tr><td><b>'+(i+1)+'</b></td><td>'+esc(r.club_name)+'</td><td>'+r.played+'</td><td>'+r.won+'</td><td>'+r.drawn+'</td><td>'+r.lost+'</td><td>'+r.goals_for+'</td><td>'+r.goals_against+'</td><td>'+r.goal_difference+'</td><td><b>'+r.points+'</b></td></tr>').join('');
    return '<div class="wl-league-panel"><h3>Official league table</h3><div class="wl-league-sub">Automatically calculated from completed fixtures using this competition’s points rules. Teams with no completed matches remain on the table.</div>'+table(['Pos','Club','P','W','D','L','GF','GA','GD','Pts'],rows)+'</div>';
  }
  async function statsView(){
    const {data,error}=await client().from('league_player_statistics').select('*').eq('business_id',business().id).eq('competition_id',competitionId).order('goals',{ascending:false}).order('assists',{ascending:false});
    if(error)throw error;
    const rows=(data||[]).map((p,i)=>'<tr><td>'+(i+1)+'</td><td><b>'+esc(p.full_name)+'</b></td><td>'+esc(p.club_name)+'</td><td>'+p.goals+'</td><td>'+p.assists+'</td><td>'+p.yellow_cards+'</td><td>'+p.red_cards+'</td></tr>').join('');
    return '<div class="wl-league-panel"><h3>Player statistics</h3><div class="wl-league-sub">Goals, assists and cards are calculated from recorded match events. Record events after a result has been verified.</div>'+table(['#','Player','Club','Goals','Assists','Yellow','Red'],rows)+'</div>'+
      (cache.players?.length?'<div class="wl-league-panel"><h3>Record match event</h3><form class="wl-league-form" data-league-form="event">'+selectField('Club','club_id',selectOptions(cache.clubs))+
      selectField('Player','player_id',selectOptions(cache.players,'id','full_name'))+selectField('Event type','event_type',['goal','own_goal','assist','yellow_card','red_card','substitution_on','substitution_off','penalty_scored','penalty_missed'].map(x=>'<option value="'+x+'">'+x.replaceAll('_',' ')+'</option>').join(''))+
      field('Minute','minute','number',false,'min="0" max="150"')+selectField('Fixture','fixture_id',selectOptions((cache.fixtures||[]).filter(f=>f.status==='completed'),'id','id','Select completed match'))+
      field('Notes','notes')+'<div class="wl-league-field full">'+button('Save match event','primary')+'</div></form></div>':'');
  }
  function disciplineView(){
    const rows=(cache.discipline||[]).map(d=>'<tr><td>'+esc(d.full_name||'—')+'</td><td>'+esc(d.club_name||'—')+'</td><td>'+esc(d.action_type)+'</td><td>'+esc(d.details)+'</td><td>'+esc(d.status)+'</td></tr>').join('');
    return '<div class="wl-league-panel"><h3>Disciplinary register</h3><div class="wl-league-sub">Record warnings, cards, suspensions and other competition decisions.</div>'+
      (cache.players?.length?'<form class="wl-league-form" data-league-form="discipline">'+selectField('Player','player_id',selectOptions(cache.players,'id','full_name'))+
      selectField('Action','action_type',['warning','yellow_card','red_card','suspension','fine','other'].map(x=>'<option value="'+x+'">'+x.replaceAll('_',' ')+'</option>').join(''))+
      field('Matches suspended','matches_suspended','number',false,'min="0" value="0"')+field('Start date','starts_on','date')+field('End date','ends_on','date')+
      '<label class="wl-league-field full"><span>Decision / details</span><textarea name="details" required></textarea></label>'+
      '<div class="wl-league-field full">'+button('Save disciplinary record','primary')+'</div></form>':empty('Register players before adding disciplinary records.'))+'</div>'+
      '<div class="wl-league-panel"><h3>Recent decisions</h3>'+table(['Player','Club','Action','Details','Status'],rows)+'</div>';
  }
  function accessView(){
    return '<div class="wl-league-panel"><h3>Competition access & roles</h3><div class="wl-league-sub">Assign existing members of this White Lion business to a competition. Use their Supabase user UUID. The person must already be an active member of this business.</div>'+
      '<form class="wl-league-form" data-league-form="access">'+field('Member user UUID','user_id','text',true)+
      selectField('Competition role','role',['competition_admin','club_manager','referee','disciplinary_officer','viewer'].map(x=>'<option value="'+x+'">'+x.replaceAll('_',' ')+'</option>').join(''))+
      selectField('Limit to club (optional)','club_id',selectOptions(cache.clubs,'id','name','All clubs'))+
      '<div class="wl-league-field full">'+button('Assign competition role','primary')+'</div></form></div>'+
      '<div class="wl-league-panel"><h3>Role responsibilities</h3>'+table(['Role','Access'],[
        '<tr><td>Competition admin</td><td>Manage seasons, clubs, players, fixtures and competition records</td></tr>',
        '<tr><td>Club manager</td><td>Maintain player registrations for the competition</td></tr>',
        '<tr><td>Referee</td><td>Submit fixture results and match events</td></tr>',
        '<tr><td>Disciplinary officer</td><td>Record and manage disciplinary decisions</td></tr>',
        '<tr><td>Viewer</td><td>Read competition records</td></tr>'
      ].join(''))+'</div>';
  }
  async function disciplineLoad(){
    if(!competitionId){cache.discipline=[];return}
    const {data,error}=await client().from('league_disciplinary_actions').select('*,league_players(full_name),league_clubs(name)').eq('business_id',business().id).eq('competition_id',competitionId).order('created_at',{ascending:false});
    if(error)throw error;
    cache.discipline=(data||[]).map(x=>({...x,full_name:x.league_players?.full_name,club_name:x.league_clubs?.name}));
  }
  async function render(){
    styles();const v=host();if(!v)return;
    if(!client()||!business()?.id){v.innerHTML=base('Sports & Local League Management','Manage local leagues, clubs, players and fixtures inside your business workspace.', '<div class="wl-league-panel">'+empty('Sign in and select an active business workspace. The league module uses your existing secure White Lion account.')+'</div>');return}
    v.innerHTML='<div class="wl-league-panel">'+empty('Loading competition records…')+'</div>';
    try{
      await load();
      let body='';
      if(!competitionId){
        body='<div class="wl-league-panel"><h3>Create your first competition</h3><div class="wl-league-sub">Start with a district league, community competition, school league, regional championship or cup tournament.</div>'+competitionForm()+'</div>';
      }else{
        if(activeTab==='overview')body=overview();
        else if(activeTab==='clubs')body=clubsView();
        else if(activeTab==='players')body=playersView();
        else if(activeTab==='fixtures')body=fixturesView();
        else if(activeTab==='table')body=await tableView();
        else if(activeTab==='stats')body=await statsView();
        else if(activeTab==='discipline'){await disciplineLoad();body=disciplineView()}
        else if(activeTab==='access')body=accessView();
      }
      v.innerHTML=base('Sports & Local League Management','Run multiple local competitions with secure administration, match records and automatic tables.',body);
      const compSel=document.getElementById('wlLeagueCompetition');if(compSel)compSel.value=competitionId;
      const seasonSel=document.getElementById('wlLeagueSeason');if(seasonSel)seasonSel.value=seasonId;
      bind();
    }catch(e){
      v.innerHTML=base('Sports & Local League Management','Your competition workspace could not be loaded.','<div class="wl-league-panel"><div class="wl-league-notice">'+esc(e.message||'Unknown error')+'</div><button class="wl-league-btn primary" id="wlLeagueRetry">Try again</button><p class="wl-league-muted">If the database migration has not been run, apply migration 015 before retrying.</p></div>');
      document.getElementById('wlLeagueRetry')?.addEventListener('click',render);
    }
  }
  function competitionForm(){
    return '<form class="wl-league-form" data-league-form="competition">'+field('Competition name','name','text',true)+
      selectField('Competition type','competition_type',['League','Cup','Tournament','School League','Community League','Other'].map(x=>'<option>'+x+'</option>').join(''))+
      field('Region / district','region')+field('Organiser','organiser')+
      field('Points for a win','points_win','number',true,'min="0" max="10" value="3"')+
      field('Points for a draw','points_draw','number',true,'min="0" max="10" value="1"')+
      field('Points for a loss','points_loss','number',true,'min="0" max="10" value="0"')+
      '<div class="wl-league-field full">'+button('Create competition','primary')+'</div></form>';
  }
  function bind(){
    document.getElementById('wlLeagueCompetition')?.addEventListener('change',e=>{competitionId=e.target.value;seasonId='';activeTab='overview';render()});
    document.getElementById('wlLeagueSeason')?.addEventListener('change',e=>{seasonId=e.target.value;render()});
    document.getElementById('wlLeagueNewCompetition')?.addEventListener('click',()=>{const n=document.getElementById('wlLeagueNotice');n.innerHTML=competitionForm();n.hidden=false;bindForms()});
    document.querySelectorAll('[data-league-tab]').forEach(b=>b.addEventListener('click',()=>{activeTab=b.dataset.leagueTab;render()}));
    document.querySelectorAll('[data-league-action]').forEach(b=>b.addEventListener('click',()=>{
      const action=b.dataset.leagueAction;
      activeTab=({ 'new-season':'overview','new-club':'clubs','new-fixture':'fixtures'})[action]||'overview';render();
    }));
    bindForms();
    document.querySelectorAll('[data-league-result]').forEach(f=>f.addEventListener('submit',async e=>{
      e.preventDefault();const data=Object.fromEntries(new FormData(f).entries());
      await save(async()=>{const {error}=await client().from('league_fixtures').update({home_score:Number(data.home_score),away_score:Number(data.away_score),status:'completed',finalised_at:new Date().toISOString(),finalised_by:cloud().getSession()?.user?.id}).eq('id',f.dataset.leagueResult).eq('business_id',business().id);if(error)throw error},'Final score saved. League table updated.');
    }));
  }
  function bindForms(){
    document.querySelectorAll('[data-league-form]').forEach(f=>f.addEventListener('submit',async e=>{
      e.preventDefault();const kind=f.dataset.leagueForm,d=Object.fromEntries(new FormData(f).entries()),b=business(),c=client();
      await save(async()=>{
        let payload={...d,business_id:b.id};
        if(kind==='competition'){payload.points_win=Number(d.points_win);payload.points_draw=Number(d.points_draw);payload.points_loss=Number(d.points_loss);payload.created_by=cloud().getSession()?.user?.id}
        if(kind==='season'){payload.competition_id=competitionId}
        if(kind==='club'){payload.competition_id=competitionId}
        if(kind==='player'){payload.competition_id=competitionId;payload.shirt_number=d.shirt_number?Number(d.shirt_number):null;payload.date_of_birth=d.date_of_birth||null}
        if(kind==='fixture'){payload.competition_id=competitionId;payload.season_id=seasonId;if(payload.home_club_id===payload.away_club_id)throw new Error('Home and away clubs must be different.');payload.kickoff_at=new Date(d.kickoff_at).toISOString()}
        if(kind==='event'){payload.competition_id=competitionId;payload.minute=d.minute?Number(d.minute):null}
        if(kind==='discipline'){payload.competition_id=competitionId;payload.matches_suspended=Number(d.matches_suspended||0);payload.starts_on=d.starts_on||null;payload.ends_on=d.ends_on||null}
        if(kind==='access'){payload.competition_id=competitionId;payload.user_id=d.user_id.trim();payload.club_id=d.club_id||null}
        const tableName=({competition:'league_competitions',season:'league_seasons',club:'league_clubs',player:'league_players',fixture:'league_fixtures',event:'league_match_events',discipline:'league_disciplinary_actions',access:'league_competition_members'})[kind];
        const {error}=await c.from(tableName).insert(payload);if(error)throw error;
        if(kind==='competition'){competitionId='';seasonId='';activeTab='overview'}
        if(kind==='season')seasonId='';
      },({competition:'Competition created.',season:'Season created.',club:'Club registered.',player:'Player registered.',fixture:'Fixture scheduled.',event:'Match event saved.',discipline:'Disciplinary record saved.',access:'Competition role assigned.'})[kind]);
    }));
  }
  async function save(work,message){
    hideNotice();try{await work();await render();notice(message)}catch(e){notice(e.message||'The change could not be saved. Check your role and database setup.')}
  }
  window.whiteLionLeague={render};
})();
