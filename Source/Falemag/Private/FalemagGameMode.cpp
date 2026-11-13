#include "FalemagGameMode.h"
#include "FalemagCharacter.h"
#include "FalemagPlayerController.h"

AFalemagGameMode::AFalemagGameMode()
{
	DefaultPawnClass = AFalemagCharacter::StaticClass();
	PlayerControllerClass = AFalemagPlayerController::StaticClass();
}
