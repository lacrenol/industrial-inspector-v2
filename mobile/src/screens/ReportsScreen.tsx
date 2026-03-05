import React, { useState, useEffect } from "react";
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
  RefreshControl
} from "react-native";
import { NativeStackScreenProps } from "@react-navigation/native-stack";
import * as SecureStore from "expo-secure-store";
import { RootStackParamList } from "../navigation";
import { colors, spacing, radius, typography } from "../theme";
import { BACKEND_BASE_URL } from "../config";

type Props = NativeStackScreenProps<RootStackParamList, "Reports">;

interface Survey {
  id: string;
  name: string;
  industry_gost: string;
}

interface Defect {
  id: string;
  survey_id: string;
  image_url: string;
  axis: string;
  construction_type: string;
  location?: string;
  description: string;
  status_category: string;
}

export const ReportsScreen: React.FC<Props> = ({ navigation }) => {
  const [surveys, setSurveys] = useState<Survey[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [expandedSurvey, setExpandedSurvey] = useState<string | null>(null);
  const [surveyDefects, setSurveyDefects] = useState<{ [key: string]: Defect[] }>({});

  useEffect(() => {
    loadSurveys();
  }, []);

  const loadSurveys = async () => {
    setLoading(true);
    setRefreshing(true);

    const isSecureStoreAvailable = await SecureStore.isAvailableAsync();
    const userId = isSecureStoreAvailable ? await SecureStore.getItemAsync("userId") : null;

    console.log("Reports: Loading surveys for real user:", userId);

    if (!userId) {
      console.log("Reports: No user ID found, navigating to Auth");
      Alert.alert("Error", "Please login first");
      navigation.replace("Auth");
      return;
    }

    try {
      const response = await fetch(`${BACKEND_BASE_URL}/surveys?user_id=${encodeURIComponent(userId)}`);
      console.log("Reports: Surveys response status:", response.status);
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      
      const data = await response.json();
      console.log("Reports: Real surveys data:", data);
      setSurveys(data);
    } catch (error) {
      console.error("Reports: Failed to load surveys:", error);
      Alert.alert("Error", "Failed to load surveys");
      // Don't set demo data
      setSurveys([]);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const loadDefectsForSurvey = async (surveyId: string) => {
    if (surveyDefects[surveyId]) {
      // Defects already loaded, just toggle expansion
      setExpandedSurvey(expandedSurvey === surveyId ? null : surveyId);
      return;
    }

    try {
      console.log("Reports: Loading defects for survey:", surveyId);
      const response = await fetch(`${BACKEND_BASE_URL}/defects/${surveyId}`);
      console.log("Reports: Defects response status:", response.status);
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      
      const defects = await response.json();
      console.log("Reports: Defects data:", defects);
      
      setSurveyDefects(prev => ({ ...prev, [surveyId]: defects }));
      setExpandedSurvey(surveyId);
    } catch (error) {
      console.error("Reports: Failed to load defects:", error);
      Alert.alert("Error", "Failed to load defects");
      // Set mock data if backend fails
      const mockDefects: Defect[] = [
        {
          id: "mock-defect-1",
          survey_id: surveyId,
          image_url: "https://example.com/image1.jpg",
          axis: "X",
          construction_type: "Concrete",
          location: "Wall section A",
          description: "Crack detected in concrete structure",
          status_category: "C"
        }
      ];
      
      setSurveyDefects(prev => ({ ...prev, [surveyId]: mockDefects }));
      setExpandedSurvey(surveyId);
    }
  };

  const generateReport = async (surveyId: string) => {
    try {
      const response = await fetch(`${BACKEND_BASE_URL}/reports/${surveyId}`);
      
      if (!response.ok) {
        throw new Error('Failed to generate report');
      }
      
      // For mobile, we'd need to handle file download differently
      // For now, just show success message
      Alert.alert(
        "Report Generated", 
        "Report has been generated successfully. In a production app, this would download the DOCX file.",
        [{ text: "OK" }]
      );
    } catch (error) {
      Alert.alert("Error", "Failed to generate report");
    }
  };

  const onRefresh = () => {
    setRefreshing(true);
    loadSurveys();
  };

  const getStatusColor = (category: string) => {
    switch (category) {
      case 'A': return colors.accent; // Green - no defect
      case 'B': return '#FFA500'; // Orange - minor
      case 'C': return '#FF6B6B'; // Red - serious
      case 'D': return '#8B0000'; // Dark red - critical
      default: return colors.textMuted;
    }
  };

  const renderSurveyItem = ({ item }: { item: Survey }) => {
    const isExpanded = expandedSurvey === item.id;
    const defects = surveyDefects[item.id] || [];
    const defectCount = defects.length;

    return (
      <View style={styles.surveyCard}>
        <TouchableOpacity
          style={styles.surveyHeader}
          onPress={() => loadDefectsForSurvey(item.id)}
        >
          <View style={styles.surveyInfo}>
            <Text style={styles.surveyName}>{item.name}</Text>
            <Text style={styles.surveyGost}>{item.industry_gost}</Text>
            <Text style={styles.defectCount}>{defectCount} defect(s)</Text>
          </View>
          <TouchableOpacity
            style={styles.generateButton}
            onPress={() => generateReport(item.id)}
            disabled={defectCount === 0}
          >
            <Text 
              style={[
                styles.generateButtonText, 
                defectCount === 0 && styles.generateButtonDisabled
              ]}
            >
              Generate
            </Text>
          </TouchableOpacity>
        </TouchableOpacity>

        {isExpanded && defects.length > 0 && (
          <View style={styles.defectsList}>
            {defects.map((defect) => (
              <View key={defect.id} style={styles.defectItem}>
                <View style={styles.defectHeader}>
                  <Text style={styles.defectLocation}>{defect.location || 'Unknown location'}</Text>
                  <View style={[styles.statusBadge, { backgroundColor: getStatusColor(defect.status_category) }]}>
                    <Text style={styles.statusText}>Category {defect.status_category}</Text>
                  </View>
                </View>
                <Text style={styles.defectDescription}>{defect.description}</Text>
                <Text style={styles.defectMeta}>
                  {defect.axis} axis • {defect.construction_type}
                </Text>
              </View>
            ))}
          </View>
        )}
      </View>
    );
  };

  if (loading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.loadingText}>Loading surveys...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <FlatList
        data={surveys}
        renderItem={renderSurveyItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContainer}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={colors.primary}
          />
        }
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyText}>No surveys found</Text>
            <Text style={styles.emptySubtext}>Create a new survey to start analyzing defects</Text>
          </View>
        }
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  listContainer: {
    padding: spacing.md,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
  },
  loadingText: {
    ...typography.body,
    color: colors.textMuted,
    marginTop: spacing.sm,
  },
  surveyCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  surveyHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: spacing.md,
  },
  surveyInfo: {
    flex: 1,
  },
  surveyName: {
    ...typography.subtitle,
    color: colors.text,
    marginBottom: spacing.xs,
  },
  surveyGost: {
    ...typography.body,
    color: colors.textMuted,
    marginBottom: spacing.xs,
  },
  defectCount: {
    ...typography.caption,
    color: colors.primary,
  },
  generateButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radius.md,
  },
  generateButtonText: {
    ...typography.body,
    color: colors.text,
    fontWeight: '600',
  },
  generateButtonDisabled: {
    color: colors.textMuted,
  },
  defectsList: {
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  defectItem: {
    padding: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  defectHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.xs,
  },
  defectLocation: {
    ...typography.body,
    color: colors.text,
    fontWeight: '600',
    flex: 1,
  },
  statusBadge: {
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    borderRadius: radius.sm,
  },
  statusText: {
    ...typography.caption,
    color: colors.text,
    fontWeight: '600',
  },
  defectDescription: {
    ...typography.body,
    color: colors.textMuted,
    marginBottom: spacing.xs,
  },
  defectMeta: {
    ...typography.caption,
    color: colors.textMuted,
  },
  emptyContainer: {
    alignItems: 'center',
    paddingVertical: spacing.xl,
  },
  emptyText: {
    ...typography.subtitle,
    color: colors.text,
    marginBottom: spacing.xs,
  },
  emptySubtext: {
    ...typography.body,
    color: colors.textMuted,
    textAlign: 'center',
  },
});
