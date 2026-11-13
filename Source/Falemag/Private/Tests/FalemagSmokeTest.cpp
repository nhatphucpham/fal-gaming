#if WITH_DEV_AUTOMATION_TESTS

#include "FalemagCharacter.h"
#include "FalemagGameMode.h"
#include "FalemagPlayerController.h"
#include "Misc/AutomationTest.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FFalemagGameModeDefaultsTest, "Falemag.GameMode.Defaults",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FFalemagGameModeDefaultsTest::RunTest(const FString& Parameters)
{
	const AFalemagGameMode* GameMode = GetDefault<AFalemagGameMode>();
	TestEqual(TEXT("Default pawn class"), GameMode->DefaultPawnClass.Get(), AFalemagCharacter::StaticClass());
	TestEqual(TEXT("Player controller class"), GameMode->PlayerControllerClass.Get(), AFalemagPlayerController::StaticClass());
	return true;
}

#endif
