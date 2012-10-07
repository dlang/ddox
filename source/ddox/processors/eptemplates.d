module ddox.processors.eptemplates;

import ddox.api;
import ddox.entities;


void mergeEponymousTemplates(Package root)
{
	void processDecls(Declaration[] decls)
	{
		foreach( ref d; decls ){
			if( auto templ = cast(TemplateDeclaration)d ){
				if( templ.members.length == 1 && templ.members[0].name == templ.name ){
					templ.members[0].templateArgs = templ.templateArgs;
					templ.members[0].parent = templ.parent;
					templ.members[0].docGroup = templ.docGroup;
					foreach( ref m; templ.docGroup.members )
						if( m is templ ) m = templ.members[0];
					d = templ.members[0];
				} else processDecls(templ.members);
			} else if( auto comp = cast(CompositeTypeDeclaration)d ){
				processDecls(comp.members);
			}
		}
	}

	root.visit!Module((mod){
		processDecls(mod.members);
	});
}
