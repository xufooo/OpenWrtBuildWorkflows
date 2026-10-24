'use strict';
'require view';
'require form';
'require fs';
'require tools.widgets as widgets';

return view.extend({
	load: function() {
		return fs.read('/var/run/r4s-accel/status').catch(function() { return ''; });
	},
	render: function(status) {
		var m = new form.Map('r4s_accel', _('Selective Acceleration'));
		var s = m.section(form.NamedSection, 'main', 'settings');
		var o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;
		o = s.option(widgets.NetworkSelect, 'lan', _('LAN network'));
		o.nocreate = true;
		o = s.option(widgets.NetworkSelect, 'wan', _('WAN network'));
		o.nocreate = true;
		o = s.option(form.DynamicList, 'hosts', _('Direct IPv4 hosts'));
		o.datatype = 'ip4addr("nomask")';
		o = s.option(form.DummyValue, '_status', _('Status'));
		o.cfgvalue = function() { return status || _('Disabled'); };
		return m.render();
	}
});
