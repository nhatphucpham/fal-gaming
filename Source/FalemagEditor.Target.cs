using UnrealBuildTool;
using System.Collections.Generic;

public class FalemagEditorTarget : TargetRules
{
	public FalemagEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_5;
		ExtraModuleNames.Add("Falemag");
	}
}
