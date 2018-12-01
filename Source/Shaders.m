#include "Shader.h"

Control *cPtr = NULL;

void setControlPointer(Control *ptr) { cPtr = ptr; }

void setPTrapActive(int index, int onoff) { cPtr->pTrap[index].active = onoff; }
void setLTrapActive(int index, int onoff) { cPtr->lTrap[index].active = onoff; }
int  getPTrapActive(int index) { return cPtr->pTrap[index].active; }
int  getLTrapActive(int index) { return cPtr->lTrap[index].active; }

void togglePointTrap(int index) { cPtr->pTrap[index].active = cPtr->pTrap[index].active > 0 ? 0 : 1; }
void toggleLineTrap(int index) { cPtr->lTrap[index].active = cPtr->lTrap[index].active > 0 ? 0 : 1; }

float* PTrapX(int index) { return &(cPtr->pTrap[index].x); }
float* PTrapY(int index) { return &(cPtr->pTrap[index].y); }
float* LTrapX(int index) { return &(cPtr->lTrap[index].x); }
float* LTrapY(int index) { return &(cPtr->lTrap[index].y); }
float* LTrapS(int index) { return &(cPtr->lTrap[index].slope); }
