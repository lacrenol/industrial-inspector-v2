import React from "react";
import { NavigationContainer, DefaultTheme, Theme } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { colors } from "./theme";
import { AuthScreen } from "./screens/AuthScreen";
import { SurveyListScreen } from "./screens/SurveyListScreen";
import { NewSurveyScreen } from "./screens/NewSurveyScreen";
import { CameraScreen } from "./screens/CameraScreen";
import { ReportsScreen } from "./screens/ReportsScreen";

export type RootStackParamList = {
  Auth: undefined;
  Surveys: undefined;
  NewSurvey: undefined;
  Camera: {
    surveyId: string;
  };
  Reports: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

const industrialDarkTheme: Theme = {
  ...DefaultTheme,
  colors: {
    ...DefaultTheme.colors,
    background: colors.background,
    card: colors.surface,
    text: colors.text,
    border: colors.border,
    primary: colors.primary,
    notification: colors.primaryAlt
  }
};

export const RootNavigator = () => {
  return (
    <NavigationContainer theme={industrialDarkTheme}>
      <Stack.Navigator
        screenOptions={{
          headerStyle: { backgroundColor: colors.surface },
          headerTintColor: colors.text,
          headerTitleStyle: { fontWeight: "600" }
        }}
      >
        <Stack.Screen
          name="Auth"
          component={AuthScreen}
          options={{ headerShown: false }}
        />
        <Stack.Screen
          name="Surveys"
          component={SurveyListScreen}
          options={{ title: "Survey Objects" }}
        />
        <Stack.Screen
          name="NewSurvey"
          component={NewSurveyScreen}
          options={{ title: "New Survey Object" }}
        />
        <Stack.Screen
          name="Camera"
          component={CameraScreen}
          options={{ title: "Capture Defect" }}
        />
        <Stack.Screen
          name="Reports"
          component={ReportsScreen}
          options={{ title: "Reports" }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
};

